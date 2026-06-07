export { 
  query, 
  getClient, 
  transaction, 
  checkConnection, 
  closePool 
} from './connection.js';

export default {
  query: (await import('./connection.js')).query,
  getClient: (await import('./connection.js')).getClient,
  transaction: (await import('./connection.js')).transaction,
  checkConnection: (await import('./connection.js')).checkConnection,
  closePool: (await import('./connection.js')).closePool,
};