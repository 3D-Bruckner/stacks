# stacks

How [portfolio.3dbruckner.de](https://portfolio.3dbruckner.de) runs [portfolio](https://github.com/3D-Bruckner/portfolio) and [vorschau.3dbruckner.de](https://vorschau.3dbruckner.de) runs [preview](https://github.com/3D-Bruckner/preview): the compose files of the server and what they need. Public, as Gamepanion's and notefeed's are; take what is useful.

| Folder    | What runs                                                                                        | Reachable                                                                                         |
| --------- | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| `portfolio/` | portfolio (SQLite and the photos in `data/`); `scripts/dump.sh` copies the databases and the photos | on the server's private address only (port 8083), where the Caddy on gewerbe-1 passes requests on |
| `preview/` | preview, the customers' model pages (SQLite and the models' files in `data/`); `scripts/dump.sh` copies the databases and the files, `tests/restore.sh` checks that a dump restores | on the server's private address only (port 8084), where the Caddy on gewerbe-1 passes requests on |

portfolio and preview run on `products-1`, next to notefeed.me, gesetze-fuer-ki.de and gamepanion.app. Caddy and the certificates are on `gewerbe-1`, the business's one public entry point.

## How it is used

This repository is checked out on the server. A companion repository, private because it holds the inventory and the secrets, writes `portfolio/.env` and `preview/.env`, runs `docker compose up` and sets up the backups. So:

- **There are no secrets and no server addresses in here.** `.env.example` lists the names; the values are written on the server.
- **Nobody edits files on the server.** A change is a commit here, then a deployment.

How it is operated (backups, restore, upgrades) is in [docs/operations.md](docs/operations.md).
