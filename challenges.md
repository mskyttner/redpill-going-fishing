Dataströmsdemo: en lämpligt lokalt tillgänglig dataström med mycket data skickas (ev via en ringbuffer) till en process som bearbetar detta i en duckdb in-memory db (antingen via ett shell script som duckdb läser från med shellfs extension eller via vanlig stdin/stdout till duckdb, se https://duckdb.org/docs/current/clients/cli/overview#reading-from-stdin-and-writing-to-stdout) - detta blir en demo/illustration av det någon sade på workshopen; någon ville se ett exempel med strömmande data... denna ström exponeras sedan i sin in tur via en in-memory databas via caddy-duckdb-module som ger MCP gentemot omvärlden och underlättar för tidsserieanalys mha llm

Portabla textgrafer: En service använder duckdb in-memory data för att servea grafer/visualiseringar i ascii/unicode/ansi-format - ev även wrappeade som html fragment men med typ monospace <pre>-wrappead output (token-compact för LLM:er och människor) exv genom att använda https://github.com/metaspartan/gotui, https://github.com/InCom-0/incplot eller andra lämpliga "text-only"-grafbibliotek (https://github.com/guptarohit/asciigraph etc) - data pipeas till tjänsten som levererar icke-javascript-baserad "grafik" i kompakt format som LLM:en sedan kan använda i sin markdown output även i TUI-sammanhang.

Infosec: En security review av andra gruppers contributions - gör lite "Red Team Review", använder lite olika skills för att hitta luckor och föreslår PRs för att täppa till hålen.

Göra ett webgränssnitt (finns ett CLI redan) för att hantera användardatabasen för caddy-duckdb-module

Göra en integration via vouch (testat med caddy-duckdb-module) gentemot RedPill-LinPro's KeyCloak-tjänst.

Ta en öppen datakälla eller RedPill-LinPro-specifik datakälla och exponera den via caddy-duckdb-module samt identifiera idéer för ytterligare finesser/tool-support under resans gång.

Prova att integrera / ge stöd för https://github.com/oauth2-proxy/oauth2-proxy (finns stöd för https://github.com/vouch/vouch-proxy men utöka även för oauth2-proxy och testa)

