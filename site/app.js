/* Wings website — small, dependency-free interactions. */
(function () {
  const nav = document.querySelector('.nav');
  const toggle = document.querySelector('.nav-toggle');
  if (nav && toggle) {
    toggle.addEventListener('click', function () {
      const open = nav.classList.toggle('open');
      toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
    nav.addEventListener('click', function (event) {
      if (event.target.tagName === 'A') nav.classList.remove('open');
    });
  }

  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const items = document.querySelectorAll('.reveal');
  if (reduce || !('IntersectionObserver' in window)) {
    items.forEach(function (el) { el.classList.add('in'); });
  } else {
    const io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('in');
          io.unobserve(entry.target);
        }
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });
    items.forEach(function (el) { io.observe(el); });
  }

  document.querySelectorAll('[data-year]').forEach(function (el) {
    el.textContent = new Date().getFullYear();
  });

  /* /open — hand the link to the installed app, keep the page usable if not. */
  const bridge = document.querySelector('[data-deeplink]');
  if (bridge) {
    const params = new URLSearchParams(window.location.search);
    const type = params.get('type') || '';
    const id = params.get('id') || '';
    const extra = params.get('extra') || '';
    const target = document.getElementById('target');
    const openBtn = document.getElementById('open-app');
    const state = document.getElementById('open-state');
    if (!type || !id) {
      if (target) target.textContent = 'الرابط غير مكتمل.';
      if (state) state.textContent = 'تأكد من نسخ الرابط كاملًا من التطبيق.';
      if (openBtn) openBtn.hidden = true;
    } else {
      const custom = 'wings://' + type + '/' + encodeURIComponent(id) +
        (extra ? '/' + encodeURIComponent(extra) : '');
      if (target) target.textContent = 'wings://' + type + '/' + id + (extra ? '/' + extra : '');
      if (openBtn) {
        openBtn.href = custom;
        openBtn.hidden = false;
      }
      const started = Date.now();
      window.location.href = custom;
      setTimeout(function () {
        if (document.hidden || Date.now() - started < 1200) return;
        if (state) state.textContent = 'لم يُفتح التطبيق. تأكد من تثبيت Wings ثم أعد المحاولة.';
      }, 1500);
    }
  }
})();
