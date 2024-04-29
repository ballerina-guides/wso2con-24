# Frontend implementation for Reviewed!

## Overview

This is the frontend implementation for Reviewed!. It consists of a React application that consumes Ballerina GraphQL services using Apollo Client.

## Prerequisites

- [Node.js version: v20.12.0](https://nodejs.org/en/blog/release/v20.12.0)
- npm (version 10.5.0 or later)

## Getting Started

1. Install the required dependencies by running the following command:

```bash
npm install
```

2. Create a `.env` file and add the following environment variables:

```bash
VITE_GRAPHQL_ENDPOINT_HTTP=https://localhost:9000/reviewed
VITE_GRAPHQL_ENDPOINT_WS=wss://localhost:9000/reviewed
```

3. Start the frontend application by running the following command:

```bash'
npm run dev
```

4. Open the browser and navigate to: [http://localhost:3000](http://localhost:3000)

## Deployment

1. Create a production build by running the following command (Optional):

```bash
npm run build
```

2. Serve the production build by running the following command:

- Serving the production build using NodeJS:

  - Run the following command:

  ```bash
  npm run preview
  ```

  - Open the browser and navigate to: [http://localhost:3000](http://localhost:3000)

- Serving the production build using python:

  - Run the following command:

  ```bash
  py -m http.server 3000 --directory dist
  ```

  - Open the browser and navigate to: [http://localhost:3000](http://localhost:3000)

  > Note: URL rewriting is not supported when serving the production build using python. (contents of ErrorPage.jsx will not render for invalid URLs)
