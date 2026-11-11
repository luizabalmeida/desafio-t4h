# Pesquisa (Etapa 3): o que a literatura e o mercado dizem sobre os problemas do diagnóstico

Como ler este arquivo
- Os problemas 1 a 5 são os de diagnostico/anotacoes.md: 1 pedidos-do-cliente; 2 pedidos-por-status; 3 top-produtos e vendas-por-dia; 4 uma conexão por consulta; 5 banco no limite.
- "Fatos da fonte" é o que o texto diz. "Interpretação" é a ligação que faço com os meus arquivos de diagnostico/. "Hipótese" é o que ainda precisa de teste medido na Etapa 4.
- Nada aqui é resultado medido. Qualquer ganho esperado é hipótese.
- Os trechos foram lidos nas fontes originais. A organização e a redação deste arquivo tiveram apoio de IA, e cada afirmação deve ser conferida contra a fonte citada.
- Data de acesso de todas as páginas web: 10/11/2026.

## Fontes

### Fonte 1: PostgreSQL 16, capítulo 11 (Indexes)
- Referência: PostgreSQL Global Development Group. PostgreSQL 16 Documentation, capítulo 11 (Indexes), seções 11.1, 11.2.1, 11.3, 11.4, 11.7 e 11.12. https://www.postgresql.org/docs/16/indexes.html. Acesso em 10/11/2026.
- Tipo: documentação oficial (técnica primária)
- Problemas: 1, 2 e 3 (e, sem investigação própria, cliente-por-email e busca-produtos)
- Fatos da fonte:
  - Sem índice, o banco varre a tabela inteira, linha por linha. Com índice, percorre uma árvore de poucos níveis. O planejador só usa o índice quando acha que é mais eficiente que a varredura sequencial, e pode precisar de ANALYZE para ter estatísticas (11.1).
  - Um índice em coluna de junção pode acelerar consultas com junção (11.1).
  - Manter índices custa nas escritas. Criar índice em tabela grande pode demorar e, por padrão, bloqueia escritas durante a criação. Índices pouco usados devem ser removidos (11.1).
  - O B-tree serve para <, <=, =, >= e > (e BETWEEN e IN). Serve para LIKE só com padrão constante e ancorado no início, e não para '%texto' (11.2.1).
  - Num índice de várias colunas, as igualdades nas colunas da esquerda e a desigualdade na primeira coluna sem igualdade limitam a parte do índice percorrida. O texto recomenda usar com moderação (11.3).
  - Um índice B-tree pode entregar as linhas já ordenadas e evitar a etapa de ordenação. Para consultas que leem uma fração grande da tabela, ordenar explicitamente tende a ser mais rápido. Com ORDER BY e LIMIT n, um índice que combine com o ORDER BY permite pegar as n primeiras linhas sem ler o resto (11.4).
  - É possível indexar uma expressão, como lower(coluna). A expressão não é recalculada na busca, mas custa na inserção e na atualização (11.7).
  - Rode ANALYZE antes de avaliar índices, use dados reais e meça com e sem o índice (11.12).
- Interpretação: sustenta índices nas colunas de filtro e de junção (problema 1), um índice de várias colunas para filtro e ordenação em pedidos-por-status (problema 2), índice sobre expressão para vendas-por-dia e para lower(email) (problema 3 e cliente-por-email). Para busca-produtos, a frase sobre '%texto' sugere que o B-tree comum não serve ao ILIKE '%termo%', mas não testei.
- A fonte não sustenta: que um índice acelere as minhas rotas, nem quanto; nada sobre OFFSET alto.

### Fonte 2: PostgreSQL 16, seção 14.1 (Using EXPLAIN)
- Referência: PostgreSQL Global Development Group. PostgreSQL 16 Documentation, seção 14.1 (Using EXPLAIN). https://www.postgresql.org/docs/16/using-explain.html. Acesso em 10/11/2026.
- Tipo: documentação oficial (técnica primária)
- Problemas: método de diagnóstico (todos)
- Fatos da fonte:
  - O plano é uma árvore de nós. Os nós de baixo leem as tabelas (varredura sequencial, por índice, bitmap) e os de cima fazem junção, agregação e ordenação.
  - Os custos são em unidades arbitrárias. Com ANALYZE, a consulta é executada de verdade e os tempos reais vêm em milissegundos.
  - Em loops, os valores de actual time e rows são médias por execução; para o total, multiplica-se pelo número de loops.
  - O nó de ordenação mostra o método (em memória ou em disco). O nó de hash mostra buckets e lotes (mais de um lote implica uso de disco).
  - Rows Removed by Filter mostra as linhas lidas e descartadas. BUFFERS ajuda a ver quais partes têm mais E/S.
  - Ressalvas: o tempo medido não inclui o envio das linhas ao cliente, a própria medição tem custo que pode ser significativo, e os resultados não devem ser extrapolados para situações bem diferentes da testada.
- Interpretação: sustenta o método usado nos arquivos 03 a 10 (ler o plano de dentro para fora, usar EXPLAIN com ANALYZE e BUFFERS) e a decisão de não usar o tempo de um EXPLAIN como resultado final.
- A fonte não sustenta: a diferença entre 2.695 ms e 123,6 ms da mesma consulta (arquivos 03 e 04). A leitura de que Rows Removed by Filter é por processo vem da minha conta (3 x 166.665 é cerca do tamanho da tabela), e não da fonte.

### Fonte 3: PostgreSQL 16, seção 20.4 (Resource Consumption)
- Referência: PostgreSQL Global Development Group. PostgreSQL 16 Documentation, seção 20.4 (Resource Consumption), subseções 20.4.1 (Memory) e 20.4.6 (Asynchronous Behavior). https://www.postgresql.org/docs/16/runtime-config-resource.html. Acesso em 10/11/2026.
- Tipo: documentação oficial (técnica primária)
- Problemas: 2 e 5
- Fatos da fonte:
  - shared_buffers: padrão de 128 MB. Em servidor dedicado com 1 GB ou mais de RAM, um ponto de partida razoável é 25% da memória. Com menos de 1 GB, uma porcentagem menor é apropriada. Só muda com reinício do servidor.
  - work_mem: memória máxima por operação (ordenação ou tabela hash) antes de escrever em arquivos temporários; padrão de 4 MB. Uma consulta pode fazer várias operações ao mesmo tempo, e várias sessões também, então o total pode ser "muitas vezes" o work_mem.
  - Ordenações servem a ORDER BY, DISTINCT e merge joins. Tabelas hash servem a hash joins e agregações por hash. O limite do hash é work_mem vezes hash_mem_multiplier (padrão 2,0).
  - maintenance_work_mem: padrão de 64 MB, usado por VACUUM, CREATE INDEX e ALTER TABLE ADD FOREIGN KEY.
  - max_parallel_workers_per_gather: padrão 2; 0 desliga a consulta paralela. Consultas paralelas podem consumir "muito mais" recursos; cada auxiliar tem impacto parecido com o de uma sessão a mais, e limites como o work_mem valem por processo.
- Interpretação: o work_mem de 4 MB (arquivo 08) é compatível com a ordenação em disco do arquivo 07. O paralelismo multiplica o uso de memória por consulta, o que importa num banco com 512 MB. Mudar parâmetros com -c no docker-compose.yml é permitido pelo desafio.
- A fonte não sustenta: que aumentar o work_mem acelere as rotas, que o paralelismo atrapalhe com 1 CPU e 20 usuários, nem o comportamento do PostgreSQL dentro de um container com limites. Não verificado.

### Fonte 4: PostgreSQL 16, seção 7.6 (LIMIT and OFFSET)
- Referência: PostgreSQL Global Development Group. PostgreSQL 16 Documentation, seção 7.6 (LIMIT and OFFSET). https://www.postgresql.org/docs/16/queries-limit.html. Acesso em 10/11/2026.
- Tipo: documentação oficial (técnica primária)
- Problemas: 2
- Fatos da fonte:
  - OFFSET pula as primeiras linhas antes de começar a devolver.
  - "The rows skipped by an OFFSET clause still have to be computed inside the server; therefore a large OFFSET might be inefficient."
  - Com LIMIT, é importante um ORDER BY que dê uma ordem única, senão o subconjunto é imprevisível. O otimizador leva o LIMIT em conta e pode escolher planos diferentes.
- Interpretação: no arquivo 07, a página 15000 (OFFSET 299.980) produziu 300 mil linhas para devolver 20. O ORDER BY de pedidos-por-status termina em id, o que dá ordem única.
- A fonte não sustenta: como evitar o problema, nem quanto custa.

### Fonte 5: PostgreSQL 16, seção 41.3 (Materialized Views)
- Referência: PostgreSQL Global Development Group. PostgreSQL 16 Documentation, seção 41.3 (Materialized Views). https://www.postgresql.org/docs/16/rules-materializedviews.html. Acesso em 10/11/2026.
- Tipo: documentação oficial (técnica primária)
- Problemas: 3 (top-produtos)
- Fatos da fonte:
  - Uma materialized view guarda o resultado de uma consulta numa estrutura parecida com uma tabela. Não pode ser atualizada diretamente; os dados novos vêm de REFRESH MATERIALIZED VIEW.
  - O acesso costuma ser bem mais rápido que consultar as tabelas de origem, mas os dados nem sempre estão atualizados.
  - É possível criar índices sobre a materialized view. O exemplo do texto é um resumo de vendas com GROUP BY e sum, atualizado por noite.
- Interpretação: o arquivo 09 mostra que top-produtos soma 19.206 produtos a cada chamada. Guardar a soma pronta é a alternativa descrita pela fonte. Num arquivo .sql novo em banco/, a criação aumentaria o tempo de subida do banco.
- A fonte não sustenta: o ganho nas minhas rotas, o custo do REFRESH em tabelas grandes, nem que o resultado fique idêntico ao atual (depende de reproduzir o filtro de status, a ordem, os tipos e o LIMIT).

### Fonte 6: node-postgres, página de pooling
- Referência: node-postgres. Documentação, página "Pooling". https://node-postgres.com/features/pooling. Acesso em 10/11/2026.
- Tipo: documentação oficial (técnica primária)
- Problemas: 4
- Fatos da fonte:
  - Conectar um cliente novo exige um handshake que pode levar de 20 a 30 ms. Pagar isso a cada consulta retardaria substancialmente a aplicação.
  - O servidor só atende um número limitado de clientes ao mesmo tempo.
  - Um único cliente conectado processa uma consulta por vez, em fila.
  - A biblioteca traz pooling embutido (Pool). Para consultas avulsas, pool.query é o jeito preferido, porque elimina o risco de vazar clientes. Todo cliente retirado do pool precisa ser devolvido.
- Opinião ou relato do autor (não usar como evidência): a anedota sobre ter derrubado um servidor de produção.
- Interpretação: o db.js cria e fecha um Client por consulta (linhas 11, 12 e 17), e uma chamada a /clientes/42/pedidos aumentou as sessões do banco em 21 contra 4 do controle (arquivos 12 e 13). A alternativa é um Pool no db.js.
- A fonte não sustenta: que o handshake local custe 20 a 30 ms (o ambiente é local, sem senha), nem o ganho. Conta minha, a testar: 17 conexões x 20 a 30 ms dão cerca de 0,35 a 0,5 s por chamada, contra uma mediana de cerca de 15,9 s; o efeito pode ser pequeno.

### Fonte 7: PgBouncer (documentação oficial)
- Referência: PgBouncer. Features, Configuration e FAQ. https://www.pgbouncer.org/features.html, https://www.pgbouncer.org/config.html e https://www.pgbouncer.org/faq.html. Versão exibida na página inicial: 1.26.1 (14/10/2026). Acesso em 10/11/2026.
- Tipo: documentação oficial (técnica primária)
- Problemas: 4
- Fatos da fonte:
  - É um serviço entre a aplicação e o banco que reaproveita conexões com o servidor.
  - Modos: sessão (padrão; a conexão com o servidor fica com o cliente enquanto ele estiver conectado), transação (só durante cada transação; quebra alguns recursos de sessão, como SET, LISTEN e PREPARE) e instrução (transações de várias instruções são proibidas).
  - Usa pouca memória (2 kB por conexão por padrão). default_pool_size padrão de 20 por par usuário/banco; max_client_conn padrão de 100.
  - Desde a versão 1.21.0, rastreia prepared statements no modo de transação se max_prepared_statements for diferente de zero.
- Interpretação: alternativa externa ao Pool da API. Se o db.js continuar criando um Client por consulta, cada consulta ainda abriria uma conexão com o PgBouncer, e o ganho seria menor que o de um Pool na própria API (hipótese minha). É um serviço novo no docker-compose.yml, e o desafio exige mostrar o custo de recursos a mais.
- A fonte não sustenta: o ganho nas minhas rotas, a compatibilidade da minha API com o modo de transação (não verificada) nem o custo de CPU do próprio PgBouncer.

### Fonte 8: Use The Index, Luke (seis páginas)
- Referência: Winand, Markus. Use The Index, Luke. Páginas: "Nested Loops" (https://use-the-index-luke.com/sql/join/nested-loops-join-n1-problem), "Querying Top-N Rows" (https://use-the-index-luke.com/sql/partial-results/top-n-queries), "Indexing Order By" (https://use-the-index-luke.com/sql/sorting-grouping/indexed-order-by), "Date Types" (https://use-the-index-luke.com/sql/where-clause/obfuscation/dates), "Paging Through Results" (https://use-the-index-luke.com/sql/partial-results/fetch-next-page) e "Performance Impacts of System Load" (https://use-the-index-luke.com/sql/testing-scalability/system-load). Acesso em 10/11/2026.
- Tipo: material técnico de autor especialista (não é documentação oficial do PostgreSQL). Muitos exemplos usam outros bancos, como Oracle.
- Problemas: 1, 2, 3 e método
- Fatos da fonte:
  - Consultas aninhadas (uma por linha do resultado anterior) somam latência de rede à de disco; é o problema "N+1 selects". Um join no banco evita essa comunicação.
  - Informar ao banco que só se quer as primeiras linhas (LIMIT) permite uma ordenação sem ler tudo, se houver índice que combine com o ORDER BY.
  - Se a ordem do índice corresponde ao ORDER BY, o banco pode omitir a ordenação explícita. A otimização vale quando o trecho percorrido do índice já está ordenado.
  - Aplicar função à coluna num filtro impede o uso de um índice simples sobre ela. Saídas: índice sobre a expressão (usando sempre a mesma expressão) ou condição de intervalo explícita. Ao usar BETWEEN com coluna que tem hora, há risco de erro na fronteira.
  - Paginação por offset: o banco conta as linhas desde o início, as páginas derivam se entram linhas novas e o tempo cresce nas páginas fundas. Paginação por chave (seek): usa o último valor da página anterior e permite pular de verdade as linhas já vistas. Exige ordem determinística, não permite ir a uma página arbitrária e é mais difícil de escrever. O PostgreSQL suporta comparação de linhas, como (a, b) < (?, ?).
  - O otimizador usa um índice por ser mais eficiente que a varredura, e não por ser o ideal. Num experimento do autor, a mesma consulta ficou cerca de 30 vezes mais lenta com 25 consultas simultâneas.
- Opinião do autor (não usar como evidência): "Execute joins in the database" e a classificação de consultas aninhadas como anti-padrão. Os números dos gráficos são de experimentos do autor e não se comparam com os meus.
- Interpretação: o rotas.js (linhas 66 a 81) faz à mão o padrão N+1. O ORDER BY de pedidos-por-status (filtro de igualdade em status e ordenação por criado_em e id) tem o formato do exemplo de índice que evita ordenação. O filtro criado_em::date de vendas-por-dia é o tipo de condição de que a página de datas trata (a página fala de TRUNC, TO_CHAR e DATE_FORMAT, e não de ::date; estender é leitura minha). A paginação por chave usa o último valor visto, e a API recebe ?pagina=, então mudar para ela alteraria a interface e pode conflitar com o contrato (a verificar).
- A fonte não sustenta: que um índice resolva o OFFSET alto. A ideia de que o tempo isolado de uma consulta não prevê o tempo sob carga é compatível com o que vi (0,1 a 2,7 s sozinha contra 8 a 24 s por rota), mas não prova a mesma causa.

### Fonte 9: Selinger et al., 1979 (artigo acadêmico)
- Referência: Selinger, P. Griffiths; Astrahan, M. M.; Chamberlin, D. D.; Lorie, R. A.; Price, T. G. Access Path Selection in a Relational Database Management System. In: Proceedings of the 1979 ACM SIGMOD International Conference on Management of Data, 1979, pp. 23-34 (paginação da cópia consultada). Cópia consultada: PDF identificado como "digital recreation" de Eric A. Brewer (2002), e não o arquivo original da ACM. Disponível em: https://courses.cs.duke.edu/compsci516/cps216/spring03/papers/selinger-etal-1979.pdf. Acesso em 10/11/2026.
- Tipo: artigo acadêmico (conferência)
- Problemas: 2 e método (contexto sobre como o otimizador escolhe entre varredura e índice)
- Fatos da fonte:
  - O usuário não especifica caminhos de acesso; o otimizador escolhe o que minimiza o "custo total". O custo soma páginas lidas e chamadas ao sistema de armazenamento ponderadas (E/S e CPU).
  - Uma varredura de segmento toca todas as páginas não vazias, cada uma uma vez. Num índice não clustered, uma página de dados pode ser lida mais de uma vez; num índice clustered, não.
  - Um índice combina com um predicado quando as colunas do predicado são um prefixo inicial das colunas do índice.
  - O otimizador compara o custo de produzir a ordem pedida por um índice com o custo do caminho mais barato mais o de ordenar. As estatísticas são atualizadas periodicamente, e não a cada escrita.
  - Nested loops: custo da externa mais N vezes o da interna.
  - Os custos previstos frequentemente não são precisos em valor absoluto, mas o caminho ótimo é escolhido na grande maioria dos casos; os autores chamam os resultados de preliminares.
- Interpretação: dá o fundamento de por que o plano mostra varredura ou índice e de por que os custos do plano não são tempos. A estimativa de uma fatia de cerca de 25% para igualdade em status (4 valores, distribuição uniforme) contra os cerca de 60% reais de "pago" (arquivo 06) ilustra o limite da suposição de uniformidade; o planejador do PostgreSQL não é o do System R, então serve só como ilustração do conceito.
- A fonte não sustenta: nada sobre LIMIT, OFFSET, pooling, materialized views, paralelismo ou o PostgreSQL 16. É um sistema experimental de 1979 com páginas de 4 kB.

### Fonte 10: Turcotte, Aldrich e Tip, 2022 (artigo acadêmico, reformulator)
- Referência: Turcotte, Alexi; Aldrich, Mark W.; Tip, Frank. reformulator: Automated Refactoring of the N+1 Problem in Database-Backed Applications. In: 37th IEEE/ACM International Conference on Automated Software Engineering (ASE '22), Rochester, MI, EUA, 10 a 14 de outubro de 2022. ACM, 12 páginas. https://doi.org/10.1145/3551349.3556911. Acesso em 10/11/2026.
- Tipo: artigo acadêmico (conferência, revisado por pares)
- Problemas: 1
- Fatos da fonte:
  - O problema N+1 acontece quando uma consulta inicial devolve N resultados que geram N consultas seguintes. Os autores dizem que consultas ao banco costumam ter alta latência.
  - A correção descrita troca as N consultas de um laço por uma consulta que busca tudo de uma vez, e depois procura o que interessa na memória (find ou filter).
  - Em 8 projetos JavaScript com Sequelize (44 casos), todas as refatorações melhoraram o desempenho, com ganhos de até 7,67 vezes, e de até 38,58 vezes com bancos maiores; as respostas HTTP ficaram iguais.
  - Houve ganhos pequenos quando o número de consultas já era baixo (mediana de 1,07 vez num aplicativo) e quando o tempo era dominado pelo processamento dos dados recebidos.
  - Os autores avisam que a análise de JavaScript não é "sound" e que as refatorações são sugestões a validar com testes.
- Interpretação: o pedidos-do-cliente tem o formato descrito (consulta dos pedidos, depois uma consulta de itens por pedido e uma de produto por item). A alternativa é buscar os itens com WHERE pedido_id IN (...) e os produtos com WHERE id IN (...), juntando no código. As regras do artigo são escritas para Sequelize, e a API usa o pg direto; o artigo diz que a ideia independe de linguagem.
- A fonte não sustenta: que os números (outros aplicativos, outro hardware) valham para o meu caso; nada sobre índices, OFFSET, pooling ou PostgreSQL. Cuidados para o contrato: manter a ordem dos itens por id e dos pedidos por criado_em DESC e id DESC, e manter itens vazios e total 0 para pedidos sem itens.

## Alternativas por problema (todas pesquisadas, nenhuma aplicada ainda)

Colunas "Desempenho esperado" são hipóteses a testar na Etapa 4. O desafio exige que recursos a mais mostrem o ganho junto com o custo.

### Problema 1: pedidos-do-cliente
| Alternativa | Fontes | Custo | Desempenho esperado (hipótese) | Risco | Esforço |
|---|---|---|---|---|---|
| Índices em pedidos(cliente_id) e itens_pedido(pedido_id) | 1, 8, 9 | Espaço e escrita mais lenta | Evita varrer a tabela em cada consulta | O planejador pode ignorar o índice | Baixo (.sql novo em banco/) |
| Trocar as consultas em sequência por consultas com IN | 8, 10 | Mais memória na API por requisição | Menos idas ao banco e menos varreduras | Mudar ordem, itens vazios ou total no contrato | Médio (muda o código) |

### Problema 2: pedidos-por-status
| Alternativa | Fontes | Custo | Desempenho esperado (hipótese) | Risco | Esforço |
|---|---|---|---|---|---|
| Índice de várias colunas (status, criado_em, id) | 1, 8, 9 | Espaço e escrita | Evita a ordenação nas páginas baixas | O OFFSET alto continua caro; índice só em status deve ajudar pouco | Baixo |
| Aumentar work_mem | 3 | Memória por operação e por processo | Menos ordenação em disco | Estourar os 512 MB do container | Baixo (-c no compose) |
| Reduzir max_parallel_workers_per_gather | 3 | Menos paralelismo por consulta | Menos disputa por 1 CPU sob carga | Consultas isoladas podem ficar mais lentas | Baixo |
| Paginação por chave (seek) | 8 | Mudança de interface | Custo constante por página | Provavelmente viola o contrato (a API recebe ?pagina=) | Alto |

### Problema 3: top-produtos e vendas-por-dia
| Alternativa | Fontes | Custo | Desempenho esperado (hipótese) | Risco | Esforço |
|---|---|---|---|---|---|
| Materialized view para top-produtos | 5 | Espaço, tempo de criação do banco, REFRESH | Ler cerca de 19 mil linhas já somadas | Dados desatualizados fora do desafio; divergência do contrato | Médio |
| Intervalo explícito em criado_em mais índice simples (vendas-por-dia) | 8, 1 | Espaço e escrita | Permite usar o índice, pois o filtro mantém cerca de 1% dos pedidos | Erro de fronteira muda o resultado | Baixo a médio |
| Índice sobre a expressão criado_em::date | 1, 8 | Custo na inserção e na atualização | Serve ao filtro atual | Só vale com a mesma expressão | Baixo |
| Índices comuns em top-produtos | 1 | Espaço e escrita | Pouco, pois a consulta usa quase todas as linhas | Efeito pequeno | Baixo; provavelmente descartada |

### Problema 4: uma conexão por consulta
| Alternativa | Fontes | Custo | Desempenho esperado (hipótese) | Risco | Esforço |
|---|---|---|---|---|---|
| Pool do node-postgres no db.js | 6 | Conexões abertas ocupam memória no banco | Evita a abertura por consulta | Vazamento de cliente se não for devolvido (pool.query evita) | Baixo |
| PgBouncer como serviço novo | 7 | CPU e memória do container extra | Reaproveita conexões com o servidor | Recursos de sessão quebram no modo de transação; a API ainda abre conexões com o pooler | Médio |
| Cliente único compartilhado | 6 | Mínimo | Pior: consultas em fila | Serializa as requisições | Baixo; descartada com base na fonte |

### Problema 5: banco no limite
| Alternativa | Fontes | Custo | Desempenho esperado (hipótese) | Risco | Esforço |
|---|---|---|---|---|---|
| Ajustar parâmetros do PostgreSQL (work_mem, shared_buffers, paralelismo) | 3 | Mais memória ou menos paralelismo | Menos trabalho por consulta | A fonte sugere cautela com shared_buffers abaixo de 1 GB; não verificado em container | Baixo |
| Aumentar CPU ou memória do container | desafio | Custo maior, que o desafio exige mostrar | Mais folga no banco | Mascara a causa | Baixo |

### Rotas ainda não investigadas
- cliente-por-email: a fonte 1 (11.7) usa lower(coluna) como exemplo de índice sobre expressão, o formato do filtro do rotas.js. Sem evidência própria sobre essa rota.
- busca-produtos: a fonte 1 (11.2.1) diz que o B-tree não serve a LIKE '%texto'; isso sugere que um índice comum não resolve o ILIKE '%termo%'. Outras alternativas não foram pesquisadas.

## Ideias para testes futuros (viram fichas em proximos-testes.md)
- Paginação por chave (fonte 8): risco de violar o contrato.
- PgBouncer (fonte 7): custo de serviço novo.
- Aumentar hash_mem_multiplier (fonte 3): o hash de top-produtos coube em memória (arquivo 09), então não há evidência de transbordamento.
- Aumentar maintenance_work_mem (fonte 3): afeta só a criação de índices.

## Limites da pesquisa
- Cinco fontes são da mesma documentação do PostgreSQL 16.
- Não foi incluído um caso de mercado verificável.
- A cópia do artigo de Selinger et al. é uma recriação digital de 2002, e não o arquivo original da ACM.
- Não foi pesquisada a extensão pg_trgm, nem alternativas para busca-produtos.
