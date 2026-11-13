// The dictionary's own script. Every word on the page is there without it; this adds the search, the topic filter,
// the word of the day, the cards' entrance, and makes every link to a word (old ones included) land and open.
(function () {
  var root = document.documentElement, body = document.body;
  var reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  var grid = document.getElementById('terms');
  if (!grid) return;
  var cards = [].slice.call(grid.querySelectorAll('.dx-card'));
  var letters = [].slice.call(grid.querySelectorAll('.dx-letter'));
  var q = document.getElementById('dx-q'), countEl = document.getElementById('dx-count');
  var clear = document.getElementById('dx-clear'), empty = document.getElementById('dx-empty');
  var emptyQ = document.getElementById('dx-empty-q'), topics = document.getElementById('dx-topics');
  var chips = [].slice.call(topics.querySelectorAll('.dx-chip'));
  var az = [].slice.call(document.querySelectorAll('.dx-az a'));
  var redirect = {};
  try { redirect = JSON.parse(document.getElementById('dx-redirect').textContent); } catch (e) {}
  var total = cards.length, group = 'all';

  // the sticky parts' heights, so a jump lands below them
  function measure() {
    var bar = document.querySelector('.bar'), tools = document.getElementById('dx-tools');
    if (bar) body.style.setProperty('--dx-bar', Math.round(bar.getBoundingClientRect().height) + 'px');
    if (tools) body.style.setProperty('--dx-tools', Math.round(tools.getBoundingClientRect().height) + 'px');
  }
  measure(); addEventListener('resize', measure);

  // --- search and topics
  var fold = function (s) {
    return s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[‘’]/g, "'")
      .replace(/[“”]/g, '"').replace(/ /g, ' ').replace(/[‐-―-]/g, ' ');
  };
  cards.forEach(function (c) {
    var word = c.querySelector('.dx-word');
    c._head = fold(word ? word.textContent : '');
    c._words = fold(c.getAttribute('data-words') || '');
    // the meaning and the DJ line; not the Deckie note, so a search finds words, not features
    c._hay = fold([].slice.call(c.querySelectorAll('.dx-word, .dx-aka, .dx-def, .dx-dj, .dx-names')).map(function (n) { return n.textContent; }).join(' '));
  });
  topics.hidden = false;

  function rank(c, words, phrase) {
    if (!words.length) return 0;
    if (!words.every(function (w) { return c._hay.indexOf(w) !== -1 || c._words.indexOf(w) !== -1; })) return -1;
    if (c._head.indexOf(phrase) === 0) return 1;
    if (c._head.indexOf(phrase) !== -1) return 2;
    if (c._words.indexOf(phrase) !== -1) return 3;
    return 4;
  }
  function apply() {
    var raw = q.value.trim(), phrase = fold(raw).replace(/\s+/g, ' '), words = phrase.split(' ').filter(Boolean), shown = 0;
    cards.forEach(function (c) {
      var r = rank(c, words, phrase), ok = r >= 0 && (group === 'all' || c.getAttribute('data-group') === group);
      c.hidden = !ok;
      c._rank = ok ? r : 99;
      if (ok) shown++;
    });
    // the grid flows in columns, like a printed dictionary, so while searching the matches are moved into rank
    // order (best first) and put back in A to Z order when the search is cleared
    var order = words.length ? cards.slice().sort(function (a, b) { return a._rank - b._rank || a._i - b._i; }) : cards;
    if (words.length || ordered) { order.forEach(function (c) { grid.appendChild(c); }); if (!words.length) restoreLetters(); }
    ordered = words.length > 0;
    body.classList.toggle('dx-searching', words.length > 0);
    body.classList.toggle('dx-filtered', group !== 'all');
    letters.forEach(function (h) { h.hidden = !cards.some(function (c) { return c._letter === h && !c.hidden; }); });
    az.forEach(function (a) { var t = document.getElementById(a.getAttribute('href').slice(1)); a.classList.toggle('off', !t || t.hidden); });
    chips.forEach(function (c) { c.setAttribute('aria-pressed', String(c.getAttribute('data-g') === group)); });
    clear.hidden = !raw;
    empty.hidden = shown > 0;
    emptyQ.textContent = raw ? '“' + raw + '”' : 'in this topic';
    countEl.textContent = shown === total ? total + ' words' : shown + ' of ' + total;
    if (words.length) cards.forEach(function (c) { if (!c.hidden) c.classList.add('in'); });
  }
  var ordered = false;
  var curL = null; [].slice.call(grid.children).forEach(function (n) { if (n.classList.contains('dx-letter')) curL = n; else n._letter = curL; });
  cards.forEach(function (c, i) { c._i = i; c._before = c.previousElementSibling && c.previousElementSibling.classList.contains('dx-letter') ? c.previousElementSibling : null; });
  function restoreLetters() { cards.forEach(function (c) { if (c._before) grid.insertBefore(c._before, c); }); }
  function reset() { q.value = ''; group = 'all'; apply(); }

  q.addEventListener('input', apply);
  q.addEventListener('keydown', function (e) {
    if (e.key === 'Enter') {   // Enter opens the best match
      e.preventDefault();
      var best = null, bo = 99;
      cards.forEach(function (c) { if (!c.hidden) { var o = c._rank || 0; if (o < bo) { bo = o; best = c; } } });
      if (best) { history.replaceState(null, '', '#' + best.id); land(best, true); }
    }
  });
  clear.addEventListener('click', function () { q.value = ''; apply(); q.focus(); });
  chips.forEach(function (c) { c.addEventListener('click', function () { group = c.getAttribute('data-g'); apply(); }); });
  document.getElementById('dx-reset').addEventListener('click', function () { reset(); q.focus(); });
  document.addEventListener('keydown', function (e) {
    var a = document.activeElement, typing = a && /^(INPUT|TEXTAREA|SELECT)$/.test(a.tagName);
    if (e.key === '/' && !typing && !e.metaKey && !e.ctrlKey) { e.preventDefault(); q.focus(); q.select(); }
    else if (e.key === 'Escape' && a === q) { if (q.value) { q.value = ''; apply(); } else q.blur(); }
  });

  // --- links to a word: clear what hides it, open its "More", mark it; old and merged ids land on their entry
  function land(card, focus) {
    if (card.hidden) reset();
    cards.forEach(function (c) { c.classList.remove('dx-hit'); });
    card.classList.add('dx-hit', 'in');
    card.scrollIntoView({ block: 'start', behavior: reduce ? 'auto' : 'smooth' });
    if (focus) { var a = card.querySelector('.dx-word a'); if (a) a.focus({ preventScroll: true }); }
  }
  function fromHash() {
    var id = decodeURIComponent(location.hash.slice(1));
    if (!id) return;
    if (redirect[id]) id = redirect[id];
    var el = document.getElementById(id);
    if (el && el.classList.contains('dx-card') && el.closest('#terms')) land(el, false);
  }
  addEventListener('hashchange', fromHash);

  // --- the word of the day: the same word all day, everywhere; picked from the DJ words (not Deckie's own)
  var feat = document.getElementById('dx-featured-card');
  var pool = cards.filter(function (c) { return c.getAttribute('data-pool') === '1'; });
  if (feat && pool.length) {
    var now = new Date(), day = Math.floor(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()) / 864e5);
    var pick = pool[(day * 7 + 3) % pool.length];   // a fixed stride, so neighbouring days are not neighbouring words
    var copy = pick.cloneNode(true);
    copy.removeAttribute('id'); copy.removeAttribute('data-words'); copy.removeAttribute('hidden');
    copy.classList.remove('dx-hit', 'in', 'dx-card');
    [].slice.call(copy.querySelectorAll('[id]')).forEach(function (n) { n.parentNode.removeChild(n); });
    [].slice.call(copy.querySelectorAll('.you')).forEach(function (n) { n.classList.remove('waiting'); });
    var h3 = copy.querySelector('h3.dx-word'), h2 = document.createElement('h2');
    if (h3) { h2.className = h3.className; h2.innerHTML = h3.innerHTML; h3.parentNode.replaceChild(h2, h3); }
    var det = copy.querySelector('.dx-more');
    if (det) {
      var open = document.createElement('div'); open.className = 'dx-open';
      [].slice.call(det.children).forEach(function (n) { if (n.tagName !== 'SUMMARY') open.appendChild(n); });
      det.parentNode.replaceChild(open, det);
    }
    feat.innerHTML = copy.innerHTML;
    feat.setAttribute('data-for', pick.id); feat.setAttribute('data-group', pick.getAttribute('data-group'));
    var lab = document.getElementById('dx-feature-h'); if (lab) lab.textContent = 'Word of the day';
  }

  // --- entrance: cards fade up as they come into view, a little apart, as the app's list settles
  if ('IntersectionObserver' in window && !reduce) {
    root.classList.add('dx-anim');
    var queue = [], timer = null;
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { queue.push(e.target); io.unobserve(e.target); } });
      if (!timer) timer = setInterval(function () {
        var c = queue.shift(); if (c) c.classList.add('in');
        if (!queue.length) { clearInterval(timer); timer = null; }
      }, 40);
    }, { rootMargin: '0px 0px -4% 0px' });
    cards.forEach(function (c) { io.observe(c); });
    setTimeout(function () { cards.forEach(function (c) { var r = c.getBoundingClientRect(); if (r.top < innerHeight && r.bottom > 0) c.classList.add('in'); }); }, 1200);   // a safety net
  }

  apply();
  if (location.hash) setTimeout(fromHash, 0);
})();
