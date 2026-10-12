<?php /** @var array $capsule @var bool $unlocked @var string|null $fileUrl */ ?>
<?php require __DIR__ . '/layout.php'; ?>
<div class="card">
  <p><strong>Откроется:</strong> <?= htmlspecialchars($capsule['open_at']) ?> (<?= $unlocked ? 'уже открыта' : 'ещё закрыта' ?>)</p>
  <?php if ($unlocked): ?>
    <pre><?= htmlspecialchars($capsule['message']) ?></pre>
    <?php if ($fileUrl): ?><p><a href="<?= htmlspecialchars($fileUrl) ?>">Скачать вложение</a></p><?php endif; ?>
  <?php else: ?>
    <p>🔒 Контент скрыт до даты открытия.</p>
  <?php endif; ?>
</div>
<a href="/">← к списку</a>
<?php require __DIR__ . '/footer.php'; ?>
