import { env } from './config/env.js';
import { createServer } from './server.js';
import logger from './utils/logger.js';

const app = createServer();

const port = env.PORT;

app.listen(port, () => {
  logger.info(`Server is running on port ${port}`);
});
