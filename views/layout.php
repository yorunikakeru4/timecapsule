<?php /** @var string $appUrl */ ?>
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <title>TimeCapsule</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 720px; margin: 2rem auto; padding: 0 1rem; color: #1a1a2e; }
    header { display: flex; justify-content: space-between; align-items: center; border-bottom: 2px solid #e94560; padding-bottom: .5rem; }
    h1 { color: #e94560; margin: 0; }
    .card { border: 1px solid #ddd; border-radius: 8px; padding: 1rem; margin: .75rem 0; }
    .locked { opacity: .55; }
    .error { background: #ffe0e0; padding: .5rem .75rem; border-radius: 6px; }
    input, textarea, button { font: inherit; padding: .4rem; width: 100%; box-sizing: border-box; }
    button { background: #e94560; color: #fff; border: 0; border-radius: 6px; cursor: pointer; width: auto; padding: .5rem 1rem; }
    footer { margin-top: 2rem; font-size: .85rem; color: #888; }
  </style>
</head>
<body>
<header>
  <h1><a href="/" style="color:inherit;text-decoration:none">TimeCapsule</a></h1>
  <nav>
    <?php if (\TimeCapsule\Auth::check()): ?>
      <span><?= htmlspecialchars(\TimeCapsule\Auth::loginName()) ?></span>
      <a href="/capsules/new">Новая капсула</a> ·
      <a href="/logout">Выйти</a>
    <?php else: ?>
      <a href="/login">Войти</a> · <a href="/register">Регистрация</a>
    <?php endif; ?>
  </nav>
</header>
<main>
