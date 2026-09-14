const tabs = [...document.querySelectorAll('[data-scene]')];
const picture = document.querySelector('#scene-image');
const panel = document.querySelector('#scene');
const images = ['orders.png', 'editor.png', 'selection.png', 'dark.png'];
let requestVersion = 0;
let displayedIndex = 0;
function markSelection(index) {
  tabs.forEach((tab, i) => {
    tab.setAttribute('aria-selected', String(i === index));
    tab.tabIndex = i === index ? 0 : -1;
  });
  panel.setAttribute('aria-labelledby', tabs[index].id);
}
async function select(index) {
  const version = ++requestVersion;
  markSelection(index);
  panel.setAttribute('aria-busy', 'true');
  const next = new Image();
  next.src = `assets/${images[index]}`;
  try {
    await next.decode();
    if (version !== requestVersion) return;
    picture.src = next.src;
    picture.alt = tabs[index].textContent;
    if (displayedIndex !== index && !window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      picture.getAnimations().forEach(animation => animation.cancel());
      picture.animate([{ opacity: 0.65 }, { opacity: 1 }], { duration: 160, easing: 'ease-out' });
    }
    displayedIndex = index;
  } catch {
    if (version === requestVersion) markSelection(displayedIndex);
  } finally {
    if (version === requestVersion) panel.setAttribute('aria-busy', 'false');
  }
}
tabs.forEach((tab, index) => {
  tab.tabIndex = index === 0 ? 0 : -1;
  tab.addEventListener('click', () => select(index));
  tab.addEventListener('keydown', event => {
    let next;
    if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
    else if (event.key === 'ArrowLeft') next = (index + tabs.length - 1) % tabs.length;
    else if (event.key === 'Home') next = 0;
    else if (event.key === 'End') next = tabs.length - 1;
    else return;
    event.preventDefault(); select(next); tabs[next].focus();
  });
});

// Purchase-time illustration: selection reveals only that row's timestamp.
const orderRows = [...document.querySelectorAll('[data-order-row]')];
function chooseOrder(index) {
  orderRows.forEach((row, i) => {
    row.classList.toggle('is-selected', i === index);
    row.classList.remove('is-expanded', 'is-dismissed');
    row.querySelector('.order-select').setAttribute('aria-pressed', String(i === index));
    const time = row.querySelector('.order-time');
    time.tabIndex = i === index ? 0 : -1;
    time.setAttribute('aria-expanded', 'false');
  });
}
orderRows.forEach((row, index) => {
  row.querySelector('.order-select').addEventListener('click', () => chooseOrder(index));
  const time = row.querySelector('.order-time');
  time.addEventListener('mouseleave', () => row.classList.remove('is-dismissed'));
  time.addEventListener('click', () => {
    row.classList.remove('is-dismissed');
    const expanded = row.classList.toggle('is-expanded');
    time.setAttribute('aria-expanded', String(expanded));
  });
  row.addEventListener('keydown', event => {
    if (event.key === 'Escape') { row.classList.add('is-dismissed'); row.classList.remove('is-expanded'); time.setAttribute('aria-expanded', 'false'); row.querySelector('.order-select').focus(); }
  });
});
document.addEventListener('click', event => {
  if (!event.target.closest('.order-row')) orderRows.forEach(row => { row.classList.remove('is-expanded'); row.querySelector('.order-time').setAttribute('aria-expanded', 'false'); });
});
