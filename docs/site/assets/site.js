// XcodeSentinel site — minimal JS (CLAUDE.md 14.1: no framework, no build).
// Responsibilities:
//   - work out the language for the current page (/en/ or /ja/)
//   - load i18n/<lang>.json and fill [data-i18n] / [data-i18n-html] nodes
//   - render shared header + footer (EN/日本語 switch jumps to SAME page)
//   - remember the choice in localStorage
//   - inject JSON-LD SoftwareApplication structured data on the home page

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
      var og = document.querySelector('meta[property="og:description"]');
      if (og) og.setAttribute("content", pd);
    }
  }

  function renderChrome(dict) {
    var lang = currentLang();
    var page = currentPage();
    var other = lang === "ja" ? "en" : "ja";

    var navKeys = {
      "index": "home",
      "getting-started": "gettingStarted",
      "guide": "guide",
      "troubleshooting": "troubleshooting",
      "privacy": "privacy",
      "faq": "faq",
      "changelog": "changelog"
    };

    var nav = PAGES.map(function (p) {
      var label = t(dict, "nav." + (navKeys[p] || p));
      var href = p === "index" ? "./" : p + ".html";
      var active = p === page ? ' class="active"' : "";
      return '<a href="' + href + '"' + active + ">" + (label || p) + "</a>";
    }).join("");

    var header = document.getElementById("site-header");
    if (header) {
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

    var portfolioUrl = t(dict, "footer.portfolioUrl") || "https://isitest1.github.io/portfolio-hub";
    var portfolioLabel = t(dict, "footer.portfolio") || "Author's other projects";
    var contactLabel = t(dict, "footer.contact") || "Contact";
    var contactEmail = "support@margheritaworks.com";
    var disclaimer = t(dict, "footer.disclaimer") || "";

    var footer = document.getElementById("site-footer");
    if (footer) {
      footer.innerHTML =
        '<div class="wrap">' +
        "<p>" + disclaimer + "</p>" +
        '<p>' +
        '<a href="' + portfolioUrl + '">' + portfolioLabel + '</a>' +
        ' · <a href="https://github.com/isitest1/XcodeSentinel">GitHub</a>' +
        ' · <a href="mailto:' + contactEmail + '">' + contactLabel + ': ' + contactEmail + '</a>' +
        '</p>' +
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

  function renderFaqItems(dict) {
    var container = document.getElementById("faq-items");
    if (!container) return;
    var items = t(dict, "faq.items");
    if (!Array.isArray(items)) return;
    container.innerHTML = '<div class="faq-list">' + items.map(function (item) {
      return '<details><summary>' + escHtml(item.q || "") + '</summary>' +
             '<div class="faq-answer">' + (item.a || "") + '</div></details>';
    }).join("") + '</div>';
  }

  function escHtml(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  function injectJsonLd(dict) {
    // Only inject on the home page
    if (currentPage() !== "index") return;
    var lang = currentLang();
    var desc = t(dict, "index.pageDescription") || "XcodeSentinel monitors your Claude coding session inside Xcode and resumes it automatically.";
    var schema = {
      "@context": "https://schema.org",
      "@type": "SoftwareApplication",
      "name": "XcodeSentinel",
      "operatingSystem": "macOS 15+",
      "applicationCategory": "DeveloperApplication",
      "inLanguage": lang,
      "offers": {
        "@type": "Offer",
        "price": "0",
        "priceCurrency": "USD"
      },
      "description": desc,
      "url": "https://isitest1.github.io/XcodeSentinel/" + lang + "/",
      "downloadUrl": "https://github.com/isitest1/XcodeSentinel/releases/latest",
      "softwareVersion": "beta",
      "author": {
        "@type": "Person",
        "name": "isitest1",
        "email": "support@margheritaworks.com",
        "url": "https://isitest1.github.io/portfolio-hub"
      },
      "license": "https://github.com/isitest1/XcodeSentinel/blob/main/LICENSE"
    };
    var script = document.createElement("script");
    script.type = "application/ld+json";
    script.textContent = JSON.stringify(schema);
    document.head.appendChild(script);
  }

  function boot() {
    var lang = currentLang();
    try {
      localStorage.setItem("xcs-lang", lang);
    } catch (e) {}

    fetch("../i18n/" + lang + ".json")
      .then(function (r) { return r.json(); })
      .then(function (dict) {
        applyI18n(dict);
        renderChrome(dict);
        renderFaqItems(dict);
        injectJsonLd(dict);
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
