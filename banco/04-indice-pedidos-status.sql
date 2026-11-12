-- Mudança 02-indice-status-ordem
-- Índice para o filtro por status e a ordenação por criado_em e id da rota pedidos-por-status.
CREATE INDEX idx_pedidos_status_criado_id ON pedidos (status, criado_em, id);
-- Atualiza as estatísticas para o planejador (pesquisa, fonte 1, seção 11.12).
ANALYZE pedidos;
