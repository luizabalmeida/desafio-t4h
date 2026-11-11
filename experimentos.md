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
