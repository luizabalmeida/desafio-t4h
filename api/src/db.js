const { Pool } = require('pg');

const config = {
  host: process.env.DB_HOST || 'localhost',
  port: Number(process.env.DB_PORT || 5432),
  user: process.env.DB_USER || 'loja',
  database: process.env.DB_NAME || 'loja',
};

// Mudança 04: conexões reaproveitadas num pool, em vez de um Client novo por consulta.
const pool = new Pool(config);

// O pool emite erro em nome de clientes ociosos se houver falha de rede ou do banco.
pool.on('error', (erro) => {
  console.error('Erro inesperado em cliente ocioso do pool', erro);
});

async function consultar(sql, parametros = []) {
  const resultado = await pool.query(sql, parametros);
  return resultado.rows;
}

module.exports = { consultar };
