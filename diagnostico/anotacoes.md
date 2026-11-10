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

## Hipóteses de causa (Passo 2.5)

Cada hipótese aponta para os arquivos de diagnostico/ que a sustentam. Nenhuma foi testada com uma mudança ainda: os arquivos mostram o que o banco faz, não o quanto isso pesa no tempo total.

### Problema 1: pedidos-do-cliente é lenta
- O que vi: mediana de cerca de 15,9 s na linha de base (resumo.txt). O cliente 42 tem 5 pedidos e 10 itens (arquivo 11) e uma chamada a ele aumentou as sessões do banco em 21, contra 4 de um controle sem chamar a API (arquivos 12 e 13). As consultas de pedidos e de itens_pedido leram as tabelas inteiras para achar 5 pedidos e 1 item (arquivos 03 e 05).
- Hipótese: a rota faz muitas consultas pequenas, uma depois da outra, e cada uma abre uma conexão nova e lê uma tabela inteira, porque não há índice nas colunas usadas.
- Estaria errada se: com índice, ou com menos consultas por chamada, o tempo da rota sob carga continuasse igual.

### Problema 2: pedidos-por-status é lenta
- O que vi: mediana de cerca de 8,7 s (resumo.txt). Para contar os pedidos pago, o banco leu a tabela toda e cerca de 60% das linhas passaram no filtro (arquivo 06). Na página 15000, com OFFSET de 299.980, ordenou 300 mil linhas em arquivos temporários no disco, de 27 a 32 MB por processo (arquivo 07), e o work_mem está em 4 MB, valor padrão (arquivo 08).
- Hipótese: a rota pesa pelo OFFSET alto e pela ordenação que não cabe na memória. Como o status pega uma fatia grande da tabela, é possível que um índice só em status ajude pouco.
- Estaria errada se: subir o work_mem ou mudar a forma de paginar não alterasse o tempo da rota.

### Problema 3: top-produtos e vendas-por-dia são lentas
- O que vi: top-produtos somou os 19.206 produtos lendo as duas tabelas grandes quase inteiras antes de aplicar o LIMIT 10 (arquivo 09). vendas-por-dia, num período de 7 dias, leu as duas tabelas inteiras para ficar com cerca de 4.300 pedidos e devolver 12.945 linhas (arquivo 10).
- Hipótese: as duas são lentas por varrer e agregar tabelas grandes a cada chamada. Em vendas-por-dia o filtro mantém só cerca de 1% dos pedidos, então um índice em criado_em parece promissor; em top-produtos, que usa quase tudo, desconfio que um índice ajude pouco.
- Estaria errada se: um índice em criado_em não mudasse o tempo de vendas-por-dia.

### Problema 4: cada consulta abre e fecha uma conexão
- O que vi: o db.js cria e fecha um Client a cada consulta (linhas 11, 12 e 17). Uma chamada a /clientes/42/pedidos aumentou as sessões em 21 contra 4 do controle, e o código previa 17 consultas (arquivos 11, 12 e 13).
- Hipótese: abrir e fechar tantas conexões tem um custo próprio, somado ao das consultas. Medi a quantidade, não o custo.
- Estaria errada se: reaproveitar conexões não reduzisse o tempo das rotas com muitas consultas.

### Problema 5: o banco está no limite
- O que vi: durante a carga o banco ficou com cerca de 99% de CPU (limite de 1 CPU) e a API com cerca de 5% (limite de 0,5 CPU), nos recursos.txt da linha de base. O PostgreSQL roda com a configuração padrão (arquivo 08).
- Hipótese: o gargalo está no banco, e os problemas 1 a 4 aparecem juntos como trabalho extra para ele. Não sei quanto cada um pesa; isso só dá para ver mudando uma coisa por vez.
- Estaria errada se: depois das melhorias a CPU do banco continuasse no teto sem ganho de tempo.

### Ainda não investigado ou não explicado
- cliente-por-email e busca-produtos: sem evidência gerada até aqui.
- O agrupamento por dia em JavaScript do vendas-por-dia (rotas.js, linhas 167 a 175).
- O contador xact_commit subiu 63 numa chamada, e eu previa algo perto de 17; não sei explicar, por isso só uso o contador de sessões.
- O cpu_max do banco apareceu menor que a CPU média nos recursos.txt.
- A diferença entre 2,7 s e 0,12 s na mesma consulta (arquivos 03 e 04).
