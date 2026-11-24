// The quick start (D46): a silent film of about a minute, bundled beside these pages (quick-start/, nothing fetched),
// offered on the first screen as a card the DJ starts, and played again from the ⋯ menu. The engine's first message
// says where the film and its poster are, whether the card is offered (it is until the DJ hides it; the engine
// remembers that in Desk's storage) and whether the film starts by itself the very first time (a switch in the core,
// DeskQuickStart.playsItselfOnFirstOpen, off). The card shows its own picture (cardPicture, since Nov 24, 2026), with
// nothing to read behind the play button; the player and the steps in words keep the poster, the film's title frame.
//
// A film that cannot play here never shows as a dead player. WebKitGTK may have no H.264 decoder, and any web view
// can fail on a file: so the card asks the web view first (canPlayType), then loads the film's first bytes quietly
// (its length and size), and the player gives up when the film errs or has not started within a few seconds. In each
// case the card and the player show the poster and the film's steps in words instead (quickStartStep.1 to .4), with
// one plain line saying the film doesn't play on this computer. No error box.
//
// No words and no design values of its own: words are DeskWords' (passed in as `t` and `list`), values desk.css's
// :root (read here with `num`).
(function () {
  "use strict";

  /// The film's encoding (desk-quickstart/README.md: H.264 Main profile, level 3.1, 1280 by 720).
  const FILM_TYPE = 'video/mp4; codecs="avc1.4D401F"';

  window.DeskQuickStart = function (d) {
    const { $, el, t, list, num, request } = d;
    let info = null;         // hello.quickStart: { film, poster, cardPicture, seconds, offer, playsItself }
    let cardFailed = false;  // the card's own picture did not load: the card shows the poster instead
    let mode = "film";       // "film" while the film can play here, "words" once it cannot
    let probed = false;
    let startedItself = false;
    let toldPlayed = false;
    let waitTimer = 0;

    const card = $("qs-card"), video = $("film-video"), dialog = $("film");

    /// The web view's own answer: "" means it has no way to play this film.
    function webViewCanPlay() {
      const v = document.createElement("video");
      return !!(v.canPlayType && v.canPlayType(FILM_TYPE));
    }

    function steps(box) { box.replaceChildren(...list("quickStartStep").map((s) => el("li", { text: s }))); }

    /// From here on the film is not offered on this computer: the card and the player show the steps in words.
    function toWords() {
      if (mode === "words") return;
      mode = "words";
      clearTimeout(waitTimer);
      try { video.pause(); } catch (e) {}
      video.removeAttribute("src");
      try { video.load(); } catch (e) {}
      draw();
    }

    /// Loads the film's first bytes once, quietly, so a film that cannot be read is known before the DJ presses play.
    function probe() {
      if (probed || !info || mode !== "film") return;
      probed = true;
      const p = document.createElement("video");
      p.muted = true; p.preload = "metadata";
      p.addEventListener("error", toWords, { once: true });
      p.src = info.film;
    }

    function draw() {
      const offered = !!(info && info.offer);
      card.hidden = !offered;
      // While the card is offered it takes the place of the crate's big drawing, so the first screen keeps its height.
      $("first").classList.toggle("offering", offered);
      card.classList.toggle("words", mode === "words");
      $("qs-play").hidden = mode === "words";
      $("qs-offer").hidden = mode === "words";
      $("qs-words").hidden = mode !== "words";
      $("film-video").hidden = mode === "words";
      $("film-words").hidden = mode !== "words";
      steps($("qs-steps")); steps($("film-steps"));
      $("qs-hide").title = t("quickStartHideHelp", { quickStartAt: t("quickStartAt.more") });
      if (info) {
        const img = $("qs-poster-img");
        // The card's own picture, with nothing to read behind the play button; the title frame (the poster) where
        // the film cannot play, as nothing covers it there, and whenever the card's picture is not sent or not there.
        const want = mode === "film" && info.cardPicture && !cardFailed ? info.cardPicture : info.poster;
        const wantsCard = want !== info.poster;
        if (img.getAttribute("src") !== want) { img.hidden = false; img.setAttribute("src", want); }
        img.onerror = () => {
          // The card's picture is not there: the poster instead.
          if (wantsCard) { cardFailed = true; draw(); return; }
          // A poster that is not there leaves no broken picture: the card keeps its words.
          img.hidden = true;
        };
      }
    }

    /// Opens the player: the film, from its start, or its steps in words when it cannot play here.
    function open() {
      if (!info) return;
      if (mode === "film" && !webViewCanPlay()) toWords();
      draw();
      if (!dialog.open) dialog.showModal();
      if (mode !== "film") return;
      if (video.getAttribute("src") !== info.film) video.setAttribute("src", info.film);
      video.poster = info.poster;
      try { video.currentTime = 0; } catch (e) {}
      // Not started within the wait (a web view that takes the file and never shows it): the steps instead.
      clearTimeout(waitTimer);
      waitTimer = setTimeout(() => { if (dialog.open && video.readyState < 2) toWords(); }, num("--qs-start-wait"));
      const p = video.play();
      if (p && p.catch) p.catch((e) => { if (!e || e.name !== "AbortError") toWords(); });
    }

    function close() {
      clearTimeout(waitTimer);
      try { video.pause(); } catch (e) {}
      if (dialog.open) dialog.close();
    }

    video.addEventListener("error", toWords);
    video.addEventListener("playing", () => {
      clearTimeout(waitTimer);
      if (!toldPlayed) { toldPlayed = true; request("quickStart.played", {}, { quiet: true }); }
    });
    dialog.addEventListener("close", () => { clearTimeout(waitTimer); try { video.pause(); } catch (e) {} });
    $("qs-play").addEventListener("click", open);
    $("qs-watch").addEventListener("click", open);
    $("qs-hide").addEventListener("click", async () => {
      if (info) info.offer = false;
      draw();
      const r = await request("quickStart.dismiss", {}, { quiet: true });
      if (r.ok && r.quickStart) info = Object.assign({}, info, r.quickStart);
    });

    return {
      /// The engine's first message: the film's facts (none from an engine before D46: no card, no menu item).
      hello(q) {
        info = q && q.film ? Object.assign({}, q) : null;
        if (info && !webViewCanPlay()) mode = "words";
        draw();
      },
      /// The first screen is showing: the card is drawn, the film checked quietly, and on the very first open, when
      /// the switch says so, the film starts by itself once.
      firstScreen() {
        if (!info) return;
        draw();
        probe();
        if (info.offer && info.playsItself && !startedItself) { startedItself = true; open(); }
      },
      available: () => !!info,
      open,
      close,
      // For the window's check (desk-shell, `--check`) and tests: what the card shows, and the way it falls back.
      state: () => ({ offered: !card.hidden, mode, canPlay: webViewCanPlay(), steps: $("qs-steps").children.length,
                      player: !$("qs-play").hidden, picture: $("qs-poster-img").getAttribute("src") }),
      fallBack: toWords,
    };
  };
})();
