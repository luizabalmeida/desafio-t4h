-- Mudança 03-indice-data
-- Índice sobre a expressão usada no filtro da rota vendas-por-dia (criado_em::date).
CREATE INDEX idx_pedidos_criado_em_data ON pedidos ((criado_em::date));
-- Atualiza as estatísticas para o planejador (pesquisa, fonte 1, seção 11.12).
ANALYZE pedidos;
