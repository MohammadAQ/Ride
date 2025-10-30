import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import swaggerUi from 'swagger-ui-express';
import YAML from 'yamljs';
import router from './routes/index.js';
import { applySecurityMiddlewares } from './middlewares/security.js';
import { errorHandler } from './middlewares/error.js';
import logger from './utils/logger.js';

// 🧩 تعريف __dirname يدوياً لأننا بنستخدم ESM modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const createServer = () => {
  const app = express();

  // 🛡️ تطبيق الميدل وير الخاصة بالأمان
  applySecurityMiddlewares(app);

  // 📦 تمكين قراءة JSON و URL Encoded
  app.use(express.json());
  app.use(express.urlencoded({ extended: true }));

  // 📘 إعداد Swagger UI
  const swaggerPath = path.resolve(__dirname, '../swagger.yaml');
  try {
    const swaggerDocument = YAML.load(swaggerPath);
    app.use('/docs', swaggerUi.serve, swaggerUi.setup(swaggerDocument));
    console.log('📘 Swagger documentation loaded successfully');
  } catch (error) {
    logger.error({ error, swaggerPath }, 'Failed to load Swagger document');
  }

  // 🛣️ جميع الراوترات تحت /api/v1
  app.use('/api/v1', router);

  // ⚠️ ميدل وير معالجة الأخطاء
  app.use(errorHandler);

  return app;
};
