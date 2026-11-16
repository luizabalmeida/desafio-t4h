# API de loja lenta sob carga: índices, pool de conexões e consultas em lote elevaram a vazão de 3,19 para 18,94 requisições por segundo

## 1. Resumo

Uma API de loja (Node.js e PostgreSQL) ficava lenta sob carga, com o banco perto de 99% de CPU. Diagnostiquei com planos de execução, pesquisei como a literatura resolve cada problema e apliquei cinco mudanças, uma por vez e sem alterar nenhuma resposta: índices, um pool de conexões e consultas em lote. Nas medianas de três execuções, a vazão foi de 3,19 para 18,94 requisições por segundo e o p95 geral (tempo abaixo do qual ficam 95% das respostas) de 19.815,7 para 3.638,4 ms. O banco continua saturado, e o p95 de uma rota ficou sem explicação.

## 2. Contexto e diagnóstico

Termos: vazão é o número de requisições atendidas por segundo; índice é a estrutura que permite achar linhas sem ler a tabela inteira; plano de execução é o caminho que o banco escolhe para uma consulta; pool é um conjunto de conexões abertas e reaproveitadas.

A API tem sete rotas de leitura sobre 100 mil clientes, 20 mil produtos, 500 mil pedidos e 1,5 milhão de itens, em dois containers (API com 0,5 CPU e banco com 1 CPU). Na linha de base (`resultados/*-00-linha-de-base/`, arquivos `resumo.txt` e `recursos.txt`), a rota `pedidos-do-cliente` tinha mediana de 16.295,9 ms e o banco usava 99,0% de CPU, contra 5,1% da API.

Como descobri: os planos de execução mostram a tabela inteira lida para devolver poucas linhas ([5 pedidos](../diagnostico/03-explain-pedidos-do-cliente.txt), [1 item](../diagnostico/05-explain-itens-do-pedido.txt)); as tabelas só têm índice na chave primária ([pedidos](../diagnostico/01-estrutura-pedidos.txt), [itens](../diagnostico/02-estrutura-itens-pedido.txt)); a consulta de pedidos por status ordena em disco ([plano](../diagnostico/16-explain-pedidos-por-status-carga-tipica.txt)); e o `db.js` abre uma conexão por consulta, com 21 sessões a mais no banco numa chamada contra 4 do controle ([12](../diagnostico/12-controle-depois.txt) e [13](../diagnostico/13-chamada-depois.txt), com o par `-antes`). Todo cliente tem 5 pedidos e de 5 a 25 itens ([23](../diagnostico/23-pedidos-por-cliente.txt), [24](../diagnostico/24-itens-por-pedido-e-por-cliente.txt)), então uma chamada faz de 12 a 32 consultas (cálculo meu).

Hipótese de causa:
- `pedidos-do-cliente`: muitas consultas pequenas, sem índice nos filtros.
- `pedidos-por-status`: o banco lê e ordena em disco todos os pedidos do status.
- `vendas-por-dia` e `top-produtos`: varrem e agregam tabelas grandes a cada chamada.
- Conexões: abrir e fechar uma conexão por consulta soma custo.
- Banco no limite: os problemas anteriores sobrecarregam seu único CPU.

## 3. Estado da arte

### Índices e leitura de planos

Segundo a documentação do PostgreSQL, sem índice o banco lê a tabela inteira, e um índice em coluna de junção pode acelerar junções [1]. O `EXPLAIN ANALYZE` executa a consulta e mostra o plano, com custos em unidades arbitrárias, não em milissegundos [2]. Selinger e colegas descrevem um otimizador que escolhe o caminho de menor custo estimado e admitem que esses custos nem sempre são precisos [4]. Winand mostra que aplicar uma função à coluna impede o índice simples e recomenda uma condição de intervalo (opinião do autor) [3].

### Paginação e ordenação

O `OFFSET`, que pula as primeiras linhas de um resultado, ainda computa as linhas puladas, então um `OFFSET` grande pode ser ineficiente [5]. Winand compara essa paginação com a paginação por chave [3]. O `work_mem`, de 4 MB por padrão, limita a memória de cada ordenação antes de ela ir para o disco [6].

### Conexões e consultas em excesso

O node-postgres diz que abrir uma conexão exige um handshake que pode levar de 20 a 30 ms e recomenda um pool [7]. O PgBouncer reaproveita conexões fora da aplicação [8]. O problema N+1, uma consulta inicial seguida de uma por resultado, aparece em Winand [3] e em Turcotte e colegas [9], que trocam as N consultas por uma só e buscam o resultado em memória, com ganhos de até 7,67 vezes em 8 projetos, e pedem validação.

### Pré-agregação

Uma materialized view guarda o resultado pronto de uma consulta, e seus dados nem sempre estão atualizados [10].

## 4. Alternativas consideradas

| Alternativa | Custo | Desempenho | Risco | Esforço |
|---|---|---|---|---|
| Índices (filtro, ordenação, expressão) | Espaço e escrita mais lenta | Medido: 3,19 → 11,08 req/s (mudanças 01 a 03) | O planejador pode ignorá-los | Baixo |
| Pool de conexões | Memória no banco | Medido: 11,08 → 18,01 req/s | Fila quando há mais consultas que conexões | Baixo |
| Consultas em lote (`ANY`: uma consulta para vários itens) | Memória na API | Medido: p95 geral 4.802,4 → 3.638,4 ms | Ordem, itens vazios e total no contrato | Médio |
| Materialized view (`top-produtos`) | Espaço e tempo de criação | Não testado | Dados desatualizados; contrato | Médio |
| Paginação por chave | Muda a interface | Não testado | Provavelmente viola o contrato | Alto |
| PgBouncer | Serviço novo (CPU e memória) | Não testado | Recursos de sessão quebram no modo de transação | Médio |

As três últimas ficaram como teste futuro porque custavam mais ou arriscavam o contrato. A paginação por chave tem boa justificativa para o `OFFSET` [3], mas a API recebe o número da página e o desafio proíbe mudar o que as rotas devolvem. A materialized view [10] atacaria o `top-produtos`, mas exige reproduzir a consulta exatamente. O PgBouncer [8] repete o que o pool na API já faz e acrescenta um serviço.

## 5. Solução escolhida e por quê

Escolhi, nesta ordem, índices (mudanças 01 a 03), pool de conexões (04) e consultas em lote (05). Comecei pelas mudanças só em SQL, que não mexem no código e deixam o contrato (as respostas que o verificador confere) mais seguro; depois mudei uma função e, por último, reescrevi uma rota. A ordem seguiu o tempo que cada rota tomava dos usuários, pela mediana vezes o número de requisições (cálculo meu, aproximado): `pedidos-do-cliente` tomava cerca de 61% na linha de base. Medi cada mudança contra a anterior para ver o efeito isolado. Deixei de lado a paginação por chave, o PgBouncer e a materialized view, pelos motivos da seção 4; estão em [proximos-testes.md](../proximos-testes.md), sem teste.

## 6. Experimento e resultado

Cada linha compara três execuções do `medir.sh` (20 usuários, 60 s) com as três da mudança anterior, em medianas; todas mantiveram o contrato e 0% de erros. CPU é a média; memória, o máximo.

| Mudança | Hipótese | p95 antes → depois | req/s antes → depois | CPU/memória | Pastas de resultados | Conclusão |
|---|---|---|---|---|---|---|
| 01-indices-fk | Índices em `cliente_id` e `pedido_id` reduzem o p95 de `pedidos-do-cliente` | 19.815,7 → 10.420,5 ms | 3,19 → 6,73 | Banco 99,0% → 99,2%, 481 → 468 MiB; API 5,1% → 10,6% | `resultados/*-00-linha-de-base/` → `resultados/*-01-indices-fk/` | Sustentada: mediana da rota 16.295,9 → 3.703,5 ms |
| 02-indice-status-ordem | Índice `(status, criado_em, id)` reduz o p95 de `pedidos-por-status` | 10.420,5 → 9.100,9 ms | 6,73 → 8,84 | Banco 99,2% → 99,9%, 468 → 494 MiB; API 10,6% → 13,6% | `*-01-indices-fk/` → `*-02-indice-status/` | Em parte: mediana da rota 5.993,5 → 1.304,1 ms; p95 da rota 10.256,0 → 8.313,4 ms |
| 03-indice-data | Índice sobre `criado_em::date` reduz o p95 de `vendas-por-dia` | 9.100,9 → 5.805,6 ms | 8,84 → 11,08 | Banco 99,9% → 99,9%, 494 → 496 MiB; API 13,6% → 12,7% | `*-02-indice-status/` → `*-03-indice-data/` | Sustentada: mediana da rota 8.155,6 → 1.714,4 ms |
| 04-pool-conexoes | O pool reduz o p95 de `pedidos-do-cliente` | 5.805,6 → 4.802,4 ms | 11,08 → 18,01 | Banco 99,9% → 99,1%, 496 → 476 MiB; API 12,7% → 13,9% | `*-03-indice-data/` → `*-04-pool-conexoes/` | Em parte: mediana da rota 3.386,5 → 1.897,4 ms; p95 da rota quase igual (5.697,9 → 5.592,9 ms) |
| 05-consultas-em-lote | Consultas em lote reduzem mediana e p95 de `pedidos-do-cliente` | 4.802,4 → 3.638,4 ms | 18,01 → 18,94 | Banco 99,1% → 99,7%, 476 → 465 MiB; API 13,9% → 13,5% | `*-04-pool-conexoes/` → `*-05-consultas-em-lote/` | Sustentada para a rota (mediana 1.897,4 → 900,5 ms; p95 5.592,9 → 3.277,5 ms); mediana geral piorou (392,6 → 514,8 ms) |

Os planos depois das mudanças mostram os índices em uso ([14](../diagnostico/14-explain-pedidos-do-cliente-com-indice.txt), [17](../diagnostico/17-explain-pedidos-por-status-com-indice-pagina-500.txt), [20](../diagnostico/20-explain-vendas-por-dia-com-indice.txt)). No acumulado, a vazão foi de 3,19 para 18,94 req/s, o p95 geral caiu cerca de 82% e a mediana geral cerca de 53%. O pool deu mais ganho do que a fonte [7] sugere: a rota `cliente`, de uma só consulta, foi de 193,3 para 100,1 ms na mediana. Não separei o motivo.

O que não funcionou: o pool não reduziu o p95 de `pedidos-do-cliente`. A mudança 05 piorou a mediana geral e as rotas de uma consulta (`cliente` foi de 100,1 para 210,6 ms), sem causa verificada. O p95 de `pedidos-por-status` subiu de 8.313,4 para 13.267,1 ms na mudança 03, que não toca essa rota. O banco segue perto de 100% de CPU.

## 7. Limites e testes futuros

Os dados são sintéticos e fixos, e a carga sorteia páginas de 1 a 1.000 e períodos de 7 dias; outros usos podem se comportar diferente, e os índices custam nas escritas, que a carga não exercita. Não verifiquei por que o p95 de `pedidos-por-status` fica em cerca de 6,7 s apesar de planos isolados rápidos ([17](../diagnostico/17-explain-pedidos-por-status-com-indice-pagina-500.txt), [21](../diagnostico/21-explain-pedidos-por-status-outros-status.txt)), nem por que a mediana geral piorou na mudança 05. Também não testei outros tamanhos de pool (o padrão é 10, [22](../diagnostico/22-pool-max-padrao.txt)), nem investiguei `cliente-por-email`, `busca-produtos` e o agrupamento em JavaScript de `vendas-por-dia`.

O efeito do `ANALYZE` (atualização das estatísticas do banco) não está separado do dos índices. A linha de base é de 06/11 e as mudanças de 11 a 13/11, no mesmo computador. Uma suspeita que o dado derrubou: clientes com muitos pedidos, já que todos têm 5. Minha conclusão cairia se, com outro pool ou mais CPU no banco, o p95 de `pedidos-por-status` caísse sem outra mudança. Não incluí um caso de mercado verificável: as fontes são documentação, um site de especialista e dois artigos acadêmicos. As ideias não testadas estão em [proximos-testes.md](../proximos-testes.md).

## 8. Referências

1. PostgreSQL Global Development Group. PostgreSQL 16 Documentation, capítulo 11 (Indexes). https://www.postgresql.org/docs/16/indexes.html. Acesso em 10/11/2026.
2. PostgreSQL Global Development Group. PostgreSQL 16 Documentation, seção 14.1 (Using EXPLAIN). https://www.postgresql.org/docs/16/using-explain.html. Acesso em 10/11/2026.
3. Winand, Markus. Use The Index, Luke. https://use-the-index-luke.com/sql/join/nested-loops-join-n1-problem, https://use-the-index-luke.com/sql/partial-results/fetch-next-page, https://use-the-index-luke.com/sql/where-clause/obfuscation/dates. Acesso em 10/11/2026.
4. Selinger, P. Griffiths; Astrahan, M. M.; Chamberlin, D. D.; Lorie, R. A.; Price, T. G. Access Path Selection in a Relational Database Management System. Proceedings of the 1979 ACM SIGMOD International Conference on Management of Data, 1979. https://courses.cs.duke.edu/compsci516/cps216/spring03/papers/selinger-etal-1979.pdf. Acesso em 10/11/2026.
5. PostgreSQL Global Development Group. PostgreSQL 16 Documentation, seção 7.6 (LIMIT and OFFSET). https://www.postgresql.org/docs/16/queries-limit.html. Acesso em 10/11/2026.
6. PostgreSQL Global Development Group. PostgreSQL 16 Documentation, seção 20.4 (Resource Consumption). https://www.postgresql.org/docs/16/runtime-config-resource.html. Acesso em 10/11/2026.
7. node-postgres. Pooling. https://node-postgres.com/features/pooling. Acesso em 10/11/2026.
8. PgBouncer. Features, Configuration e FAQ. https://www.pgbouncer.org/features.html, https://www.pgbouncer.org/config.html, https://www.pgbouncer.org/faq.html. Acesso em 10/11/2026.
9. Turcotte, Alexi; Aldrich, Mark W.; Tip, Frank. reformulator: Automated Refactoring of the N+1 Problem in Database-Backed Applications. 37th IEEE/ACM International Conference on Automated Software Engineering (ASE '22), 2022. https://doi.org/10.1145/3551349.3556911. Acesso em 10/11/2026.
10. PostgreSQL Global Development Group. PostgreSQL 16 Documentation, seção 41.3 (Materialized Views). https://www.postgresql.org/docs/16/rules-materializedviews.html. Acesso em 10/11/2026.

## 9. Uso de IA

Usei IA (Claude) para organizar o passo a passo, interpretar as saídas dos planos de execução, estruturar a pesquisa e redigir rascunhos das anotações e deste artigo. Rodei todos os comandos, li os trechos das fontes que cito e conferi os números contra os arquivos do repositório. Os números de antes e depois vêm do `medir.sh`, e as medianas foram calculadas a partir dos valores de cada `resumo.txt`.
