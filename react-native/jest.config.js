/** @type {import('jest').Config} */
module.exports = {
  testEnvironment: 'node',
  testMatch: ['<rootDir>/src/**/__tests__/**/*.test.ts'],
  transform: {
    '^.+\\.ts$': [
      'ts-jest',
      {
        diagnostics: false,
        tsconfig: {
          strict: true,
          esModuleInterop: true,
          module: 'commonjs',
          moduleResolution: 'node',
          target: 'ES2020',
          skipLibCheck: true,
          types: ['jest', 'node'],
        },
      },
    ],
  },
};
