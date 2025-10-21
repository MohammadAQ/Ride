import express from 'express';
import path from 'path';
import swaggerUi from 'swagger-ui-express';
import YAML from 'yamljs';
import router from './routes/index.js';
import { applySecurityMiddlewares } from './middlewares/security.js';
import { errorHandler } from './middlewares/error.js';
import logger from './utils/logger.js';

export const createServer = () => {
  const app = express();

  applySecurityMiddlewares(app);

  app.use(express.json());
  app.use(express.urlencoded({ extended: true }));

  const swaggerPath = path.resolve(process.cwd(), 'backend/swagger.yaml');
  try {
    const swaggerDocument = YAML.load(swaggerPath);
    app.use('/docs', swaggerUi.serve, swaggerUi.setup(swaggerDocument));
  } catch (error) {
    logger.error({ error, swaggerPath }, 'Failed to load Swagger document');
  }

  app.use('/api/v1', router);

  app.use(errorHandler);

  return app;
};
