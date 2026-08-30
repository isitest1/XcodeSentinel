// XcodeSentinel site — minimal JS (CLAUDE.md 14.1: no framework, no build).
// Responsibilities:
//   - work out the language for the current page (/en/ or /ja/)
//   - load i18n/<lang>.json and fill [data-i18n] / [data-i18n-html] nodes
//   - render the shared header + footer, including the EN/日本語 switch that
//     jumps to the SAME page in the other language (CLAUDE.md 14.2)
//   - remember the choice in localStorage

(function () {
  "use strict";

  var PAGES = [
    "index",
    "getting-started",
    "guide",
    "troubleshooting",
    "privacy",
    "faq",
    "changelog",
  ];

  function currentLang() {
    return document.documentElement.lang === "ja" ? "ja" : "en";
  }

  // "…/ja/guide.html" -> "guide"; "…/ja/" -> "index"
  function currentPage() {
    var file = location.pathname.split("/").pop() || "index.html";
    if (file === "" || file === "index.html") return "index";
    return file.replace(/\.html$/, "");
  }

  function otherLangHref(lang, page) {
    var file = page === "index" ? "" : page + ".html";
    return "../" + lang + "/" + file;
  }

  function t(dict, key) {
    return key.split(".").reduce(function (o, k) {
      return o && o[k] != null ? o[k] : null;
    }, dict);
  }

  function applyI18n(dict) {
    document.querySelectorAll("[data-i18n]").forEach(function (el) {
      var v = t(dict, el.getAttribute("data-i18n"));
      if (v != null) el.textContent = v;
    });
    document.querySelectorAll("[data-i18n-html]").forEach(function (el) {
      var v = t(dict, el.getAttribute("data-i18n-html"));
      if (v != null) el.innerHTML = v; // source is our own JSON
    });
    var page = currentPage();
    var pt = t(dict, page + ".pageTitle");
    if (pt) document.title = pt + " — XcodeSentinel";
    var pd = t(dict, page + ".pageDescription");
    if (pd) {
      var m = document.querySelector('meta[name="description"]');
      if (m) m.setAttribute("content", pd);
    }
  }

  function renderChrome(dict) {
    var lang = currentLang();
    var page = currentPage();
    var other = lang === "ja" ? "en" : "ja";

    var nav = PAGES.map(function (p) {
      var label = t(dict, "nav." + (p === "getting-started" ? "gettingStarted" : p === "index" ? "home" : p));
      var href = p === "index" ? "./" : p + ".html";
      var active = p === page ? ' class="active"' : "";
      return '<a href="' + href + '"' + active + ">" + (label || p) + "</a>";
    }).join("");

    var header = document.getElementById("site-header");
    if (header) {
      header.className = "site-header";
      header.innerHTML =
        '<div class="wrap">' +
        '<a class="brand" href="./">XcodeSentinel</a>' +
        "<nav>" + nav + "</nav>" +
        '<span class="lang-switch"><a href="' +
        otherLangHref(other, page) +
        '" data-set-lang="' + other + '">' +
        (t(dict, "nav.langLabel") || (other === "ja" ? "日本語" : "English")) +
        "</a></span>" +
        "</div>";
    }

    var footer = document.getElementById("site-footer");
    if (footer) {
      footer.className = "site-footer";
      footer.innerHTML =
        '<div class="wrap">' +
        "<p>" + (t(dict, "footer.disclaimer") || "") + "</p>" +
        '<p><a href="' + (t(dict, "footer.portfolioUrl") || "#") + '">' +
        (t(dict, "footer.portfolio") || "") + "</a>" +
        ' · <a href="https://github.com/isitest1/XcodeSentinel">GitHub</a></p>' +
        "</div>";
    }

    document.querySelectorAll("[data-set-lang]").forEach(function (el) {
      el.addEventListener("click", function () {
        try {
          localStorage.setItem("xcs-lang", el.getAttribute("data-set-lang"));
        } catch (e) {}
      });
    });
  }

  function boot() {
    var lang = currentLang();
    try {
      localStorage.setItem("xcs-lang", lang);
    } catch (e) {}

    fetch("../i18n/" + lang + ".json")
      .then(function (r) {
        return r.json();
      })
      .then(function (dict) {
        applyI18n(dict);
        renderChrome(dict);
      })
      .catch(function () {
        // Leave the fallback markup in place if the JSON fails to load.
      });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
