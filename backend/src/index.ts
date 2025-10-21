import { env } from './config/env';
import { createServer } from './server';
import logger from './utils/logger';

const app = createServer();

const port = env.PORT;

app.listen(port, () => {
  logger.info(`Server is running on port ${port}`);
});
