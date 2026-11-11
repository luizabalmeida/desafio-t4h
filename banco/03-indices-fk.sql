-- Mudança 01-indices-fk
-- Índices nas colunas de filtro e de junção da rota pedidos-do-cliente.
CREATE INDEX idx_pedidos_cliente_id ON pedidos (cliente_id);
CREATE INDEX idx_itens_pedido_pedido_id ON itens_pedido (pedido_id);
-- Atualiza as estatísticas para o planejador (pesquisa, fonte 1, seção 11.12).
ANALYZE pedidos;
ANALYZE itens_pedido;
