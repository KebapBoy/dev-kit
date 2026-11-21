<?php

declare(strict_types=1);

// Front controller: every request comes here (nginx in the image, php -S in the devcontainer)
$path = (string) parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);

// PHP's built-in server: let it serve files that exist in public/, as nginx does
if (PHP_SAPI === 'cli-server' && $path !== '/' && is_file(__DIR__ . $path)) {
    return false;
}

if ($path === '/healthz') {
    // Liveness for the container health check, the reverse proxy and dev-kit deploy, which waits
    // until it reports the version it deployed
    header('Content-Type: application/json');
    echo json_encode([
        'status' => 'ok',
        'version' => trim((string) file_get_contents(__DIR__ . '/../VERSION')),
    ]);
    return;
}

// The app
