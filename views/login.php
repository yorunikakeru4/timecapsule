<?php /** @var string|null $error */ ?>
<?php require __DIR__ . '/layout.php'; ?>
<?php if (!empty($error)): ?><p class="error"><?= htmlspecialchars($error) ?></p><?php endif; ?>
<form method="post" action="/login">
  <p><input name="login" placeholder="Логин" required></p>
  <p><input name="password" type="password" placeholder="Пароль" required></p>
  <p><button>Войти</button></p>
</form>
<?php require __DIR__ . '/footer.php'; ?>
