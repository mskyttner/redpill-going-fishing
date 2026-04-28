package main

import (
	"bufio"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
)

const capacity = 10_000

type RingBuffer struct {
	mu     sync.Mutex
	buf    [capacity]string
	head   int // next write position
	count  int // number of valid entries
	header string
}

func (r *RingBuffer) add(line string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.buf[r.head] = line
	r.head = (r.head + 1) % capacity
	if r.count < capacity {
		r.count++
	}
}

// drain returns header + all buffered lines as CSV and resets the buffer.
func (r *RingBuffer) drain() string {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.count == 0 {
		return r.header + "\n"
	}

	lines := make([]string, r.count)
	start := (r.head - r.count + capacity) % capacity
	for i := range r.count {
		lines[i] = r.buf[(start+i)%capacity]
	}

	r.head = 0
	r.count = 0

	return r.header + "\n" + strings.Join(lines, "\n") + "\n"
}

func main() {
	addr := flag.String("addr", ":9001", "HTTP listen address")
	flag.Parse()

	rb := new(RingBuffer)

	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 1<<20), 1<<20) // 1 MB line buffer

	if scanner.Scan() {
		rb.header = scanner.Text()
	}

	go func() {
		for scanner.Scan() {
			rb.add(scanner.Text())
		}
		if err := scanner.Err(); err != nil {
			log.Printf("stdin error: %v", err)
		}
	}()

	http.HandleFunc("/drain", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/csv")
		fmt.Fprint(w, rb.drain())
	})

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		rb.mu.Lock()
		n := rb.count
		rb.mu.Unlock()
		fmt.Fprintf(w, `{"buffered":%d,"capacity":%d}`, n, capacity)
	})

	log.Printf("ring buffer listening on %s", *addr)
	log.Fatal(http.ListenAndServe(*addr, nil))
}
