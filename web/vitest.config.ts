import {defineConfig} from 'vitest/config';
// Node 25+ ships its own localStorage global, which shadows jsdom's; turn it off so tests use jsdom storage.
export default defineConfig({test:{include:['src/**/*.test.ts'],execArgv:['--no-experimental-webstorage'],environmentOptions:{jsdom:{url:'http://localhost:5173'}}}});
