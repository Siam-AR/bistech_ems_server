import 'dotenv/config';
import { defineConfig } from 'prisma/config';

export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    directory: 'prisma/migrations',
  },
  database: {
    connectionString: process.env.DATABASE_URL || 'postgresql://ems_app:postgres@localhost:5432/ems?schema=public',
  },
});
