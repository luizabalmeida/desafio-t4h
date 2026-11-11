# Experimentos (Etapa 4)

Como ler este arquivo
- Cada mudança tem um rótulo (01, 02...) e um commit próprio. Os resultados ficam em commits separados, em resultados/.
- Todo número de antes e depois sai do scripts/medir.sh (três execuções com o mesmo rótulo; comparo a mediana).
- O "antes" de cada mudança é a medição da mudança anterior; a primeira compara com a linha de base 00-linha-de-base.
- Mudanças que não melhoraram também entram aqui.

## Hipóteses (escritas antes de medir)
- 01-indices-fk: criar índices em pedidos(cliente_id) e itens_pedido(pedido_id) deve reduzir o p95 da rota pedidos-do-cliente e aumentar as requisições por segundo, porque o banco passa a achar os pedidos e os itens de um cliente sem ler as tabelas inteiras. Estaria errada se o tempo da rota sob carga não mudasse. Fontes: diagnostico/03 e 05; pesquisa, fontes 1 e 8.

## Tabela de resultados
| Mudança | Fonte da ideia | Status | Antes (pasta) | Depois (pasta) | Resultado (medianas) | Conclusão |
|---|---|---|---|---|---|---|
| 01-indices-fk | diagnostico/03 e 05; pesquisa, fontes 1 e 8 | Aplicada e medida | resultados/20261106-104830-00-linha-de-base, resultados/20261106-105045-00-linha-de-base, resultados/20261106-105228-00-linha-de-base | resultados/20261111-183948-01-indices-fk, resultados/20261111-184509-01-indices-fk, resultados/20261111-184733-01-indices-fk | Geral: 3,19 para 6,73 req/s; p95 19.815,7 para 10.420,5 ms; mediana 1.102,7 para 791,6 ms; p99 23.350,6 para 23.836,3 ms. pedidos-do-cliente: mediana 16.295,9 para 3.703,5 ms; p95 20.727,9 para 5.994,8 ms. CPU média do banco 99,0% para 99,2%, da API 5,1% para 10,6%. Contrato mantido nas 6 execuções. | Hipótese sustentada para a rota-alvo (mediana caiu cerca de 77%). Não separei o efeito dos índices do efeito do ANALYZE, que estava no mesmo arquivo. Outras rotas melhoraram menos e a causa não foi verificada. O banco continua com cerca de 99% de CPU, e vendas-por-dia e top-produtos não mudaram. Linha de base medida em 06/11 e esta em 11/11, no mesmo computador. |
