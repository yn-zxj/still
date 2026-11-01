document.documentElement.classList.add("js");

const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
const pageItems = document.querySelectorAll(".page-enter");
const revealItems = document.querySelectorAll(".reveal");

for (const item of [...pageItems, ...revealItems]) {
  const delay = item.dataset.delay;
  if (delay) item.style.setProperty("--delay", `${delay}ms`);
}

if ("IntersectionObserver" in window && !reduceMotion.matches) {
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add("is-visible");
      observer.unobserve(entry.target);
    }
  }, { threshold: 0.1, rootMargin: "0px 0px -5% 0px" });

  for (const item of revealItems) observer.observe(item);
} else {
  for (const item of revealItems) item.classList.add("is-visible");
}

const navToggle = document.querySelector(".nav-toggle");
const nav = document.querySelector(".site-nav");

function closeNavigation() {
  nav?.classList.remove("is-open");
  navToggle?.setAttribute("aria-expanded", "false");
}

navToggle?.addEventListener("click", () => {
  const isOpen = navToggle.getAttribute("aria-expanded") === "true";
  navToggle.setAttribute("aria-expanded", String(!isOpen));
  nav?.classList.toggle("is-open", !isOpen);
});

for (const link of nav?.querySelectorAll("a") ?? []) {
  link.addEventListener("click", closeNavigation);
}

document.addEventListener("click", (event) => {
  if (!nav?.classList.contains("is-open")) return;
  if (event.target instanceof Node && !nav.parentElement?.contains(event.target)) {
    closeNavigation();
  }
});

window.addEventListener("keydown", (event) => {
  if (event.key === "Escape") closeNavigation();
});

const tabs = [...document.querySelectorAll(".reminder-tab")];
const reminderImage = document.querySelector("#reminder-image");
const reminderCaption = document.querySelector("#reminder-caption");
const reminderTitle = document.querySelector("#reminder-title");
const reminderBody = document.querySelector("#reminder-body");

const reminderDimensions = {
  "reminder-mini-course.webp": [880, 1320],
  "reminder-full.webp": [3024, 1964],
  "reminder-banner.webp": [676, 100]
};

function activateReminderTab(tab, moveFocus = false) {
  for (const item of tabs) {
    const active = item === tab;
    item.classList.toggle("is-active", active);
    item.setAttribute("aria-selected", String(active));
    item.tabIndex = active ? 0 : -1;
  }

  if (moveFocus) tab.focus();

  const nextImage = tab.dataset.image;
  if (!nextImage || !reminderImage) return;

  const filename = nextImage.split("/").at(-1);
  const dimensions = reminderDimensions[filename];
  reminderImage.classList.add("is-switching");

  window.setTimeout(() => {
    if (dimensions) {
      reminderImage.width = dimensions[0];
      reminderImage.height = dimensions[1];
    }
    reminderImage.src = nextImage;
    reminderImage.alt = tab.dataset.caption ?? "";
    if (reminderCaption) reminderCaption.textContent = tab.dataset.caption ?? "";
    if (reminderTitle) reminderTitle.innerHTML = tab.dataset.title ?? "";
    if (reminderBody) reminderBody.textContent = tab.dataset.body ?? "";
    reminderImage.classList.remove("is-switching");
  }, reduceMotion.matches ? 0 : 130);
}

for (const [index, tab] of tabs.entries()) {
  tab.tabIndex = tab.classList.contains("is-active") ? 0 : -1;
  tab.addEventListener("click", () => activateReminderTab(tab));
  tab.addEventListener("keydown", (event) => {
    if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
    event.preventDefault();

    let targetIndex = index;
    if (event.key === "ArrowLeft") targetIndex = (index - 1 + tabs.length) % tabs.length;
    if (event.key === "ArrowRight") targetIndex = (index + 1) % tabs.length;
    if (event.key === "Home") targetIndex = 0;
    if (event.key === "End") targetIndex = tabs.length - 1;
    activateReminderTab(tabs[targetIndex], true);
  });
}

const dialog = document.querySelector("#lightbox");
const dialogImage = dialog?.querySelector("img");
const dialogCaption = dialog?.querySelector("p");
const closeButton = dialog?.querySelector(".lightbox-close");

for (const figure of document.querySelectorAll("[data-lightbox]")) {
  figure.tabIndex = 0;
  figure.setAttribute("role", "button");
  figure.setAttribute("aria-haspopup", "dialog");

  const openLightbox = () => {
    const image = figure.querySelector("img");
    if (!image || !dialog || !dialogImage) return;

    dialogImage.src = image.currentSrc || image.src;
    dialogImage.alt = image.alt;
    if (dialogCaption) {
      dialogCaption.textContent =
        figure.querySelector("figcaption")?.textContent?.trim() ??
        image.alt;
    }
    dialog.showModal();
  };

  const image = figure.querySelector("img");
  figure.setAttribute("aria-label", `查看大图：${image?.alt ?? "界面截图"}`);
  figure.addEventListener("click", openLightbox);
  figure.addEventListener("keydown", (event) => {
    if (!["Enter", " "].includes(event.key)) return;
    event.preventDefault();
    openLightbox();
  });
}

closeButton?.addEventListener("click", () => dialog?.close());
dialog?.addEventListener("click", (event) => {
  if (event.target === dialog) dialog.close();
});

const progress = document.querySelector(".scroll-progress span");
let progressQueued = false;

function updateScrollProgress() {
  progressQueued = false;
  if (!progress) return;

  const scrollable = document.documentElement.scrollHeight - window.innerHeight;
  const ratio = scrollable > 0 ? Math.min(window.scrollY / scrollable, 1) : 0;
  progress.style.width = `${ratio * 100}%`;
}

window.addEventListener("scroll", () => {
  if (progressQueued) return;
  progressQueued = true;
  window.requestAnimationFrame(updateScrollProgress);
}, { passive: true });

window.addEventListener("resize", updateScrollProgress);
updateScrollProgress();
