# Blackoff

Co-op online zombie survival in 3D, running as a Telegram Mini App on phones.

- `client/`: Godot 4.7 project (GDScript, Compatibility renderer, single-threaded Web export)
- `server/`: authoritative Node.js + TypeScript game server (WebSocket, binary protocol)
- `shared/`: JSON data read by both: constants, protocol, weapons, zombies, waves
- `tools/`: setup, export, smoke-test and (later) deploy scripts
- `deploy/`: environment template and server configuration snippets
- `docs/`: status, architecture, asset licenses, TODO

Start here: [docs/DEVELOPMENT_STATUS.md](docs/DEVELOPMENT_STATUS.md).
