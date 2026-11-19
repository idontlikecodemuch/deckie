// The demo page's player: the songs in the list, one after another, then from the top again. Play and pause, next,
// and a tap on a song jumps to it. Nothing is sent anywhere; the page reads only its own files. With scripts off, each
// song in the list is a plain link to its file.
(function () {
  var audio = document.getElementById('dm-audio'), player = document.querySelector('.dm-player');
  var links = [].slice.call(document.querySelectorAll('#dm-songs a'));
  if (!audio || !player || !links.length) return;
  var title = document.getElementById('dm-now-h'), artist = document.getElementById('dm-artist'), count = document.getElementById('dm-count');
  var play = document.getElementById('dm-play'), next = document.getElementById('dm-next');
  var fill = document.getElementById('dm-fill'), clock = document.getElementById('dm-clock');
  var i = 0;

  // The last two words of a line kept together, as the page sets every line.
  function keep(s) { return s.replace(/ (\S+)$/, ' $1'); }
  function time(s) { s = Math.max(0, Math.floor(s || 0)); return Math.floor(s / 60) + ':' + ('0' + (s % 60)).slice(-2); }

  function show(n) {
    i = (n + links.length) % links.length;
    var a = links[i];
    title.textContent = keep(a.dataset.title);
    artist.textContent = keep(a.dataset.artist);
    count.textContent = 'Song ' + (i + 1) + ' of ' + links.length;
    links.forEach(function (l, k) { if (k === i) l.setAttribute('aria-current', 'true'); else l.removeAttribute('aria-current'); });
    fill.style.width = '0'; clock.textContent = '0:00';
    if ('mediaSession' in navigator && window.MediaMetadata) {
      navigator.mediaSession.metadata = new MediaMetadata({ title: a.dataset.title, artist: a.dataset.artist, album: 'The Deckie demo' });
    }
  }
  function load(n, go) {
    show(n);
    audio.src = links[i].getAttribute('href');
    audio.preload = 'auto';
    if (go) audio.play().catch(function () {});
  }
  function playing(on) {
    player.classList.toggle('on', on);
    play.setAttribute('aria-label', on ? 'Pause' : 'Play');
  }

  play.addEventListener('click', function () {
    if (!audio.getAttribute('src')) { load(i, true); return; }
    if (audio.paused) audio.play().catch(function () {}); else audio.pause();
  });
  next.addEventListener('click', function () { load(i + 1, true); });
  links.forEach(function (l, k) { l.addEventListener('click', function (e) { e.preventDefault(); load(k, true); }); });
  audio.addEventListener('ended', function () { load(i + 1, true); });
  audio.addEventListener('play', function () { playing(true); });
  audio.addEventListener('pause', function () { playing(false); });
  audio.addEventListener('timeupdate', function () {
    var d = audio.duration;
    if (d) fill.style.width = (100 * audio.currentTime / d) + '%';
    clock.textContent = time(audio.currentTime) + (d ? ' / ' + time(d) : '');
  });
  if ('mediaSession' in navigator) {
    try { navigator.mediaSession.setActionHandler('nexttrack', function () { load(i + 1, true); }); } catch (e) {}
  }
  show(0);
})();
