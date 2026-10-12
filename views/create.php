<?php /** @var string|null $error */ ?>
<?php require __DIR__ . '/layout.php'; ?>
<h2>Новая капсула</h2>
<?php if (!empty($error)): ?><p class="error"><?= htmlspecialchars($error) ?></p><?php endif; ?>
<form method="post" action="/capsules" enctype="multipart/form-data">
  <p><textarea name="message" rows="6" placeholder="Сообщение в будущее…" required></textarea></p>
  <p><input type="datetime-local" name="open_at" required></p>
  <p><input type="file" name="attachment" accept="image/*,application/pdf"></p>
  <p><button>Запечатать</button></p>
</form>
<?php require __DIR__ . '/footer.php'; ?>
