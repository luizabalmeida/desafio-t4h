# Próximos testes (ideias pesquisadas e não testadas)

Status de todas as fichas: Pesquisada, teste futuro.

Como ler: nenhuma ideia abaixo foi aplicada. O que acredito que ganharia é hipótese, sem resultado medido. Os números citados vêm de arquivos deste repositório (resultados/ e diagnostico/). A numeração das fontes é a de pesquisa/anotacoes-pesquisa.md.

## Ficha 1: materialized view para top-produtos
- Origem: PostgreSQL 16, seção 41.3 (Materialized Views): https://www.postgresql.org/docs/16/rules-materializedviews.html (fonte 5). O diagnóstico está em diagnostico/09: a consulta soma 19.206 produtos antes do LIMIT.
- O que acredito que ganharia: a rota deixaria de somar os itens de todos os pedidos a cada chamada e leria o resultado já agregado. Nas três medições da mudança 05 a mediana da rota ficou em cerca de 8,7 s, com 17 a 19 requisições por execução (resultados/20261113-083721-05-consultas-em-lote, 083905 e 084320). Apesar do peso de 2%, a rota segura um usuário por vários segundos a cada chamada (conta aproximada minha).
- Como testaria: um .sql novo em banco/ com CREATE MATERIALIZED VIEW que agregue unidades e receita por produto, com o filtro status diferente de cancelado; trocar a consulta da rota para ler da view, mantendo a ordem (receita decrescente, depois id) e o LIMIT; conferir o contrato; medir três vezes.
- O que precisaria: reproduzir exatamente o filtro, a ordem e os tipos dos números, para o contrato continuar passando, e decidir se o custo de criar a view na subida do banco é aceitável.
- Limite: a fonte avisa que os dados da view podem ficar desatualizados. No desafio os dados são fixos, mas numa aplicação real seria preciso uma política de REFRESH. Não verifiquei o custo do REFRESH.

## Ficha 2: paginação por chave (seek) em pedidos-por-status
- Origem: Use The Index, Luke, "Paging Through Results": https://use-the-index-luke.com/sql/partial-results/fetch-next-page (fonte 8); PostgreSQL 16, seção 7.6 (LIMIT and OFFSET): https://www.postgresql.org/docs/16/queries-limit.html (fonte 4).
- O que acredito que ganharia: hoje o plano percorre OFFSET mais 20 entradas do índice (10.000 na página 500 e 20.000 na página 1000, arquivos 17 e 18); com seek percorreria só as do resultado. O tempo isolado dessas consultas foi de cerca de 14 a 16 ms (arquivos 17 e 18), então o ganho em tempo pode ser pequeno. O ganho esperado é em trabalho por consulta, não medido.
- Como testaria: um protótipo fora do contrato, com uma consulta que compare (criado_em, id) com o último par visto, e comparar plano e tempo com a atual. Só entraria na API se a interface pudesse ser mantida.
- O que precisaria: decidir com a T4H se a interface ?pagina=N pode mudar. O desafio proíbe mudar o que a rota devolve.
- Limite: a fonte diz que o seek não permite ir a uma página arbitrária. A API recebe o número da página, então provavelmente viola o contrato.

## Ficha 3: PgBouncer
- Origem: PgBouncer, Features, Configuration e FAQ: https://www.pgbouncer.org/features.html, https://www.pgbouncer.org/config.html e https://www.pgbouncer.org/faq.html (fonte 7). O diagnóstico está em diagnostico/12 e 13.
- O que acredito que ganharia: reaproveitar conexões fora da API. Com o Pool da mudança 04 a API já reaproveita conexões, então o ganho adicional é incerto. Ele apareceria se o número de conexões com o banco virasse problema, o que não observei (max_connections de 100 em diagnostico/08, carga de 20 usuários).
- Como testaria: um serviço novo no docker-compose.yml entre a API e o banco; apontar DB_HOST e DB_PORT para ele; medir três vezes e comparar também CPU e memória de todos os containers.
- O que precisaria: escolher o modo de pooling (sessão é o padrão; transação quebra recursos de sessão) e verificar a compatibilidade da API. O desafio exige mostrar o custo do serviço extra.
- Limite: não verifiquei o custo de CPU do PgBouncer num container.

## Ficha 4: tamanho do pool de conexões
- Origem: observação de diagnostico/22 (padrão de 10 conexões, medido na biblioteca instalada) e o resultado misto da mudança 05; documentação do node-postgres sobre pooling: https://node-postgres.com/features/pooling (fonte 6). O parâmetro max não está descrito na página que li, então a documentação dele precisa ser consultada antes.
- O que acredito que ganharia: com 20 usuários e um pool de 10, até 10 consultas esperam na fila da API. Um pool maior pode reduzir a espera ou aumentar a disputa pelo único CPU do banco; não sei qual efeito pesa mais.
- Como testaria: criar o Pool com max igual a 5, 10 e 20, uma mudança por vez, medindo três vezes cada.
- O que precisaria: confirmar na documentação o parâmetro e o comportamento da fila, e manter a mesma máquina e a mesma carga.
- Limite: a mudança 05 teve efeito misto em rotas de uma consulta que não expliquei. A suspeita, não testada, é a fila do pool ou a disputa pelo CPU do banco.

## Ficha 5: parâmetros do PostgreSQL (paralelismo e work_mem)
- Origem: PostgreSQL 16, seção 20.4 (Resource Consumption): https://www.postgresql.org/docs/16/runtime-config-resource.html (fonte 3). O diagnóstico está em diagnostico/08, 19 e 20.
- O que acredito que ganharia: os planos usam 2 processos auxiliares (Workers Launched igual a 2 nos arquivos 19 e 20) num banco limitado a 1 CPU. Desligar o paralelismo (max_parallel_workers_per_gather igual a 0) poderia reduzir a disputa por CPU. O work_mem de 4 MB causava a ordenação em disco do arquivo 16, que o índice da mudança 02 eliminou nos planos que vi (arquivos 17, 18, 19 e 21), então aumentar o work_mem provavelmente rende pouco agora.
- Como testaria: um parâmetro com -c no command do serviço banco do docker-compose.yml, uma mudança por vez, medindo três vezes.
- O que precisaria: o desafio permite mudar a configuração do PostgreSQL com -c. Verificar com SHOW que o valor foi aplicado.
- Limite: a fonte avisa que consultas paralelas podem consumir mais recursos, mas não diz o efeito com 1 CPU num container. Não verificado.

## Ficha 6: índice sobre lower(email) para cliente-por-email
- Origem: PostgreSQL 16, seção 11.7 (Indexes on Expressions): https://www.postgresql.org/docs/16/indexes-expressional.html (fonte 1), cujo exemplo é lower(coluna). Na rota, o filtro é lower(email) igual a lower($1) (api/src/rotas.js, linha 47).
- O que acredito que ganharia: trocar a leitura da tabela de clientes por uma busca por índice. A mediana da rota ficou entre cerca de 0,4 e 0,6 s nas mudanças 04 e 05, com 15% do peso das requisições. Não gerei o plano dessa consulta, então não sei se hoje ela lê a tabela inteira.
- Como testaria: primeiro um EXPLAIN com ANALYZE e BUFFERS da consulta; se mostrar varredura, criar o índice sobre lower(email) em um .sql novo, conferir o contrato e medir.
- O que precisaria: o plano atual como evidência de diagnóstico.
- Limite: a fonte avisa que índice sobre expressão custa nas escritas e só vale se a consulta usar a mesma expressão.

## Ficha 7: busca-produtos (ILIKE com curinga nos dois lados)
- Origem: PostgreSQL 16, seção 11.2.1 (B-tree): https://www.postgresql.org/docs/16/indexes-types.html (fonte 1), que diz que o B-tree serve a LIKE só com padrão ancorado no início, e não a '%texto'. A extensão pg_trgm aparece na fonte 5 (https://www.postgresql.org/docs/16/rules-materializedviews.html) apenas num exemplo de busca por semelhança; não verifiquei se ela serve a ILIKE com curinga.
- O que acredito que ganharia: não sei. A mediana da rota foi de cerca de 0,2 a 0,4 s nas mudanças 04 e 05, mais baixa que a das outras rotas, então o ganho provável é pequeno.
- Como testaria: ler a documentação da extensão pg_trgm do PostgreSQL 16, confirmar se a imagem postgres:16.4 a traz, gerar o plano atual e comparar com um índice de trigramas.
- O que precisaria: uma pesquisa adicional, ainda não feita.
- Limite: ideia incompleta.

## Ficha 8: mais CPU para o container do banco
- Origem: enunciado do desafio (seção 07: limites de CPU e memória podem mudar, desde que o ganho seja mostrado junto com o custo). Não pesquisada em fonte externa.
- O que acredito que ganharia: o banco ficou com cerca de 99% a 100% de CPU em todas as medições (recursos.txt de cada pasta). Mais CPU poderia aliviar esse gargalo.
- Como testaria: aumentar o limite de CPU do serviço banco no docker-compose.yml e medir três vezes. O medir.sh registra os limites e o consumo de todos os containers.
- O que precisaria: mostrar o ganho junto com o custo, como o enunciado exige.
- Limite: mascara a causa e custa mais. Não testei.

## Ideias pesquisadas sem ficha própria
- hash_mem_multiplier e maintenance_work_mem (fonte 3): o hash de top-produtos coube em memória (diagnostico/09) e maintenance_work_mem só afeta a criação de índices, então não vi evidência de que valha testar.
