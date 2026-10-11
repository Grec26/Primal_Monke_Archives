# Primal Monke WebXR

A separate browser port of this repository's original Unity prototype. Includes the forest arena, arm-driven VR locomotion, five fleeing monkeys, a 90-second tag round, and an on-screen mode. Uses Three.js and original primitive art; no files from the human itch.io game are included.

## Run locally

Use Node.js 22 or newer:

```sh
cd web
npm ci
npm run dev
```

Open the address Vite prints on the same computer. On screen: WASD/arrows move, drag the scene to look, Space jumps, click or E tags a nearby monkey, and R restarts. Phones have touch buttons and drag-to-look controls.

## Play in a headset

Host the production build over **HTTPS**, then open it in a WebXR-capable headset browser (such as Meta Quest Browser) and choose **Enter VR**. WebXR also permits localhost on the same device; a computer's plain HTTP LAN address is insufficient for headset access. Allow immersive VR permissions and use both tracked controllers and a configured guardian boundary.

Push the floor, trunks, branches, or rocks to move; brace and pull to climb, and release a push to launch. Touch each monkey's torso to tag. The round board near spawn displays time and score. Press the right controller's A button to restart. Tracking loss or a hidden XR session pauses the round. Exit VR using the headset browser's session controls.

## Build and host

### GitHub Pages website

The repository includes an automatic deployment workflow in `.github/workflows/pages.yml`.

1. Open [repository Pages settings](https://github.com/Grec26/Primal_Monke_Archives/settings/pages).
2. Under **Build and deployment → Source**, select **GitHub Actions**.
3. Open [the deployment workflow](https://github.com/Grec26/Primal_Monke_Archives/actions/workflows/pages.yml), choose **Run workflow**, and select `main`.

After a successful deployment, the website will be at **https://grec26.github.io/Primal_Monke_Archives/**. Future changes to `web/` on `main` redeploy automatically. The workflow runs the game logic tests, builds the site with relative asset paths for the repository subdirectory, and publishes only the web build. GitHub Pages provides HTTPS for headset access. Initial Pages activation and the live URL have not been verified from the cloud workspace.

### Other static hosts

```sh
cd web
npm run build
```

Upload the **contents of `web/dist`** to an HTTPS static host, preserving the `assets` directory. Relative asset paths allow subdirectory hosting. For itch.io HTML5 hosting, zip the contents with `index.html` at the ZIP root. Embedded WebXR requires the host iframe to allow `xr-spatial-tracking`; if immersive VR is unavailable in the embed, use a standalone HTTPS host.

## Checks

```sh
npm test
npm run build
npx playwright install chromium
npm run test:browser
```

With an existing Chromium installation, set `CHROMIUM_PATH` to its executable when running browser tests. Six Node tests cover swept collisions, wall sliding, floor collision, tagging, timeout, and tracking pauses. Browser checks exercise rendering, starting a round, countdown, input, restart, menu return, and a small viewport.

Production build, Node tests, and desktop Chromium checks passed in the cloud workspace. Real headset tracking, arm movement, headset comfort, and mobile touch hardware remain untested. The collision approximation and AI are prototype implementations; multiplayer, persistence, and hand tracking without controllers are not implemented.
