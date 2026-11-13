// Deckie: the small script both pages share. Everything on the pages works without it.
(function () {
  var root = document.documentElement, reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  root.classList.add('js');

  // 1. The script words are written in the first time each is seen. A word is hidden only once its heading is
  //    being watched, so if anything fails every word simply shows.
  if ('IntersectionObserver' in window && !reduce) {
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) {
        if (!e.isIntersecting) return;
        e.target.querySelectorAll('.you').forEach(function (w, n) { setTimeout(function () { w.classList.remove('waiting'); w.classList.add('written'); }, 150 + n * 350); });
        io.unobserve(e.target);
      });
    }, { rootMargin: '0px 0px -8% 0px' });
    document.querySelectorAll('.you').forEach(function (w) { if (!w.closest('.top')) { w.classList.add('waiting'); io.observe(w.parentElement); } });
  }

  // 1b. Tiles rise as they come into view, a row at a time; the pitch tile counts up to the deck's reading. Final
  //     states are the page's own, so with no script or with reduced motion everything is simply there.
  var rise = [].slice.call(document.querySelectorAll('.tile, .steps li.pick, .pick.wide'));
  if (rise.length && 'IntersectionObserver' in window && !reduce) {
    root.classList.add('anim');
    rise.forEach(function (el) { el.classList.add('rise'); var sibs = [].slice.call(el.parentElement.children); el.style.setProperty('--i', sibs.indexOf(el) % 3); });
    var count = function (el) {
      var a = +el.dataset.from, b = +el.dataset.to, plus = el.classList.contains('pct'), t0 = performance.now();
      (function step(now) { var k = Math.min(1, (now - t0) / 1200), e = 1 - Math.pow(1 - k, 3), v = a + (b - a) * e;
        el.textContent = plus ? '+' + v.toFixed(1) : (k < 1 ? v.toFixed(1) : String(b)); if (k < 1) requestAnimationFrame(step); })(t0);
    };
    var io2 = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (!e.isIntersecting) return; e.target.classList.add('in'); io2.unobserve(e.target);
        if (e.target.id === 't-pitch') setTimeout(function () { e.target.querySelectorAll('[data-to]').forEach(count); }, 350); });
    }, { rootMargin: '0px 0px -10% 0px' });
    rise.forEach(function (el) { io2.observe(el); });
  }

  // 1c. The dictionary panel: two words show, and every few seconds the whole column moves up by one card in a
  //     single eased move (the leaving card fades as it goes, the next is already underneath), so nothing jumps.
  //     The panel's height is fixed to the tallest pair. It waits while the pointer or the keyboard is on it, runs
  //     only while it is on screen and the tab is showing, and never under reduced motion.
  var deck = document.querySelector('.deck#terms');   // the home panel only; the dictionary page has its own #terms
  if (deck && deck.children.length > 2 && !reduce && 'IntersectionObserver' in window) {
    var track = document.createElement('div'); track.className = 'track';
    while (deck.firstChild) track.appendChild(deck.firstChild);
    deck.appendChild(track); deck.classList.add('live');
    var GAP = 10, busy = false, seen = false, held = false;
    var fit = function () { var k = [].slice.call(track.children).filter(function (e) { return e.nodeType === 1; }), m = 0;
      for (var i = 0; i < k.length; i++) m = Math.max(m, k[i].offsetHeight + k[(i + 1) % k.length].offsetHeight + GAP);
      deck.style.height = m + 'px'; };
    fit(); addEventListener('resize', fit);
    var turn = function () {
      if (busy || !seen || held || document.hidden) return;
      var first = track.firstElementChild, dy = first.offsetHeight + GAP; busy = true;
      track.style.transition = 'transform 0.6s cubic-bezier(.3,0,.2,1)'; first.style.transition = 'opacity 0.5s ease';
      track.style.transform = 'translateY(' + (-dy) + 'px)'; first.style.opacity = '0';
      setTimeout(function () { track.style.transition = 'none'; first.style.transition = 'none'; track.appendChild(first);
        track.style.transform = 'none'; first.style.opacity = ''; busy = false; }, 640);
    };
    setInterval(turn, 4200);
    new IntersectionObserver(function (es) { seen = es[0].isIntersecting; }, { threshold: 0.3 }).observe(deck);
    ['mouseenter', 'focusin'].forEach(function (e) { deck.addEventListener(e, function () { held = true; }); });
    ['mouseleave', 'focusout'].forEach(function (e) { deck.addEventListener(e, function () { held = false; }); });
  }

  // 2. Home: the name is large in the hero, so the bar shows its small copy only once the large one has scrolled away.
  var big = document.querySelector('.wordmark');
  if (big && 'IntersectionObserver' in window) {
    root.classList.add('has-wordmark');
    new IntersectionObserver(function (es) { root.classList.toggle('past-wordmark', !es[0].isIntersecting); }, { rootMargin: '-64px 0px 0px 0px' }).observe(big);
  }

  // 3. A faint waveform, fixed behind the page: mirrored bars, as Deckie Booth draws a song. It is made from
  //    arithmetic, not from any recording. It drifts slowly; it stands still under reduced motion and stops while
  //    the tab is hidden.
  var c = document.createElement('canvas'); c.id = 'wave'; c.setAttribute('aria-hidden', 'true');
  document.body.insertBefore(c, document.body.firstChild);
  var x = c.getContext('2d'), W = 0, H = 0, dpr = 1, timer = null, t0 = performance.now(); window.__wave = function (t) { t0 = performance.now() - t * 1000; draw(); };
  function h01(i) { var s = Math.sin(i * 127.1 + 311.7) * 43758.5453; return s - Math.floor(s); }      // a fixed number per bar
  function smooth(p) { var i = Math.floor(p), f = p - i, s = f * f * (3 - 2 * f); return h01(i) * (1 - s) + h01(i + 1) * s; }
  function level(p) {                                                                                   // a song's shape: sections, phrases, beats
    var section = 0.35 + 0.65 * smooth(p / 96), phrase = 0.55 + 0.45 * smooth(p / 13 + 40), beat = 0.45 + 0.55 * h01(Math.floor(p));
    var kick = Math.floor(p) % 4 === 0 ? 1 : 0.72;
    return section * phrase * beat * kick;
  }
  function size() { dpr = Math.min(window.devicePixelRatio || 1, 1.5); W = innerWidth; H = innerHeight; c.width = Math.round(W * dpr); c.height = Math.round(H * dpr); draw(); }
  // Each bar's height is its fixed shape times three slow movements: a swell every nine seconds or so, a ripple that
  // travels along the bars, and a soft pulse at 122 beats a minute. All are sines, so nothing flickers.
  function layer(t, speed, step, bar, amp, seed, lo, hi) {
    var shift = t * speed, first = Math.floor(shift / step), off = shift % step, mid = H * 0.56;
    var swell = 0.78 + 0.22 * Math.sin(t * 0.7 + seed), beat = 0.5 + 0.5 * Math.sin(t * 12.78);
    for (var i = -1; i * step < W + step; i++) {
      var n = first + i + seed, ripple = 0.5 + 0.5 * Math.sin(t * 1.9 + n * 0.21);
      var v = level(n) * swell * (0.72 + 0.28 * ripple) * (0.94 + 0.06 * beat), h = Math.max(2, v * amp);
      x.fillStyle = 'rgba(180,150,255,' + (lo + (hi - lo) * v).toFixed(3) + ')';
      x.fillRect(i * step - off, mid - h, bar, h * 2);
    }
  }
  function draw() {
    var t = reduce ? 2.2 : (performance.now() - t0) / 1000;
    x.setTransform(dpr, 0, 0, dpr, 0, 0); x.clearRect(0, 0, W, H);
    layer(t, 2, 13, 7, Math.min(H * 0.46, 460), 700, 0.02, 0.045);    // behind: wider, taller, slower
    layer(t, 4, 7, 3, Math.min(H * 0.34, 340), 0, 0.045, 0.1);        // in front
  }
  function run() { stop(); if (!reduce && !document.hidden) timer = setInterval(draw, 33); }           // thirty frames a second: smooth for a slow swell, half the cost of sixty
  function stop() { if (timer) { clearInterval(timer); timer = null; } }
  addEventListener('resize', size); document.addEventListener('visibilitychange', run);
  size(); run();
})();
