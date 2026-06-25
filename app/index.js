const express = require('express');
const { Pool } = require('pg');

const app = express();
const PORT = process.env.PORT || 3000;

const pool = new Pool({
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT) || 5432,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

pool.on('error', (err) => {
  console.error('Unexpected DB client error:', err.message);
});

async function initDB() {
  const client = await pool.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS employees (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100),
        department VARCHAR(100),
        salary INTEGER
      );
    `);
    const { rowCount } = await client.query('SELECT * FROM employees');
    if (rowCount === 0) {
      await client.query(`
        INSERT INTO employees (name, department, salary) VALUES
          ('Alice Johnson', 'Engineering', 95000),
          ('Bob Smith', 'Marketing', 72000),
          ('Carol White', 'Engineering', 88000),
          ('David Brown', 'HR', 65000),
          ('Eva Green', 'Engineering', 102000),
          ('Frank Lee', 'Finance', 78000),
          ('Grace Kim', 'Marketing', 69000);
      `);
      console.log('Database seeded successfully');
    }
  } finally {
    client.release();
  }
}

app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.get('/employees', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM employees ORDER BY id');
    res.json({ count: result.rowCount, employees: result.rows });
  } catch (err) {
    console.error('DB error:', err.message);
    res.status(500).json({ error: 'Database error', detail: err.message });
  }
});

app.get('/', (req, res) => {
  res.json({
    message: 'NAGP K8s Assignment — Employee API',
    endpoints: { employees: '/employees', health: '/health' }
  });
});

initDB()
  .then(() => {
    app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
  })
  .catch(err => {
    console.error('Failed to initialize DB:', err.message);
    process.exit(1);
  });