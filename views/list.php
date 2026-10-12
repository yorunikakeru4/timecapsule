<?php /** @var array $capsules */ ?>
<?php require __DIR__ . '/layout.php'; ?>
<h2>Мои капсулы</h2>
<?php if (!$capsules): ?>
  <p>Капсул пока нет. <a href="/capsules/new">Создайте первую</a> — письмо в будущее.</p>
<?php endif; ?>
<?php foreach ($capsules as $c): $locked = strtotime($c['open_at']) > time(); ?>
  <div class="card <?= $locked ? 'locked' : '' ?>">
    <strong><a href="/capsules/<?= (int)$c['id'] ?>">Капсула #<?= (int)$c['id'] ?></a></strong>
    — откроется <?= htmlspecialchars($c['open_at']) ?>
    <?= $locked ? '🔒' : '🔓' ?>
    <?php if ($c['file_name']): ?> · с файлом<?php endif; ?>
  </div>
<?php endforeach; ?>
<p><em>LR3</em></p>
<?php require __DIR__ . '/footer.php'; ?>
