# Anotações do diagnóstico (06/11/2026)

Fonte dos números: resultados/20261106-105045-00-linha-de-base/ (execução do meio das três)

## Observei

### Nos resultados da linha de base
1. A mediana de tempo vai de ≈ 0,2 s (cliente) a ≈ 24 s (top-produtos). (resumo.txt)
2. As três mais lentas pela mediana: top-produtos (24161 ms), pedidos-do-cliente (15877 ms), pedidos-por-status (8699 ms). (resumo.txt)
3. Pelo cálculo requisições × mediana, pedidos-do-cliente concentra ≈ 61% do tempo, pedidos-por-status ≈ 18% e vendas-por-dia ≈ 10%. (cálculo meu sobre o resumo.txt)
4. top-produtos é a mais lenta, mas teve só 3 requisições (peso 2%). (resumo.txt)
5. Banco: CPU média ≈ 99,6% (limite 1 CPU) e memória máxima ≈ 481 MiB (limite 512 MiB). (recursos.txt, contexto.txt)
6. API: CPU média ≈ 5,1% (limite 0,5 CPU) e memória máxima ≈ 43 MiB (limite 256 MiB). (recursos.txt, contexto.txt)
7. Sem erros; contrato mantido. (resumo.txt, contrato.txt)

### No código
8. db.js, linhas 11, 12 e 17: cada chamada de consultar() cria um Client, conecta e desconecta. Não há reaproveitamento de conexões.
9. rotas.js, linhas 66 a 81: pedidos-do-cliente faz uma consulta para o cliente, uma para os pedidos, uma por pedido e uma por item, em sequência.
10. rotas.js, linhas 112 a 116: pedidos-por-status faz um count(*) e uma consulta com ORDER BY ... LIMIT ... OFFSET; o contrato testa pagina=15000.
11. rotas.js, linhas 193 a 205: top-produtos junta itens_pedido, pedidos e produtos, soma por produto e só depois aplica LIMIT.
12. rotas.js, linha 162: vendas-por-dia filtra com p.criado_em::date; linha 159 traz p.observacoes e as linhas 167 a 175 agrupam por dia em JavaScript.
13. rotas.js, linha 47: cliente-por-email filtra com lower(email); linha 136: busca-produtos usa ILIKE '%termo%'.
14. banco/01-estrutura.sql: só há PRIMARY KEY em id; o arquivo não cria outros índices (falta conferir no banco real).
15. docker-compose.yml: o serviço banco não tem command, então usa a configuração padrão do PostgreSQL.
16. Dúvida em aberto: no recursos.txt, a CPU média do banco (99,6%) aparece maior que a CPU máxima (99,0%); não usar cpu_max até entender a origem. (recursos.txt)

## Suspeito (hipóteses a testar, ainda sem evidência)
- S1: pedidos-do-cliente é lenta por fazer dezenas de consultas por requisição e por filtrar cliente_id e pedido_id sem índice. Confirmo com EXPLAIN e com \d de pedidos e itens_pedido.
- S2: pedidos-por-status é lenta por contar e ordenar muitos pedidos sem índice em status e pelo OFFSET alto. Confirmo com EXPLAIN.
- S3: top-produtos e vendas-por-dia são lentas por varrer e agregar tabelas grandes. Confirmo com EXPLAIN.
- S4: abrir e fechar uma conexão por consulta tem custo próprio, multiplicado pelo número de consultas por requisição. Confirmo medindo.
- S5: a configuração padrão do PostgreSQL pode não estar ajustada ao limite de 512 MB. Confirmo com SHOW.
