# Ride Monorepo

This repository hosts the Ride application as a monorepo with a Flutter frontend
and a secure Node.js backend.

## Project structure

```
/
├── backend   # Node.js + Express REST API
└── frontend  # Flutter client application
```

## Backend

### Prerequisites
- Node.js 20+
- npm

### Getting started

```bash
cd backend
npm install
cp .env.example .env      # fill in Firebase Admin credentials and CORS settings
npm run dev                # start the development server on http://localhost:8080
```

The API is available under `http://localhost:8080/api/v1` and Swagger UI can be
accessed at `http://localhost:8080/docs`.

## Frontend

### Prerequisites
- Flutter SDK

### Getting started

```bash
cd frontend
flutter pub get
flutter run
```

The Flutter app authenticates with Firebase and communicates with the backend
exclusively through REST endpoints.
