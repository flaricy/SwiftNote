const tabs = [...document.querySelectorAll('[data-scene]')];
const picture = document.querySelector('#scene-image');
const panel = document.querySelector('#scene');
const images = ['orders.png', 'editor.png', 'selection.png', 'dark.png'];
function select(index) {
  tabs.forEach((tab, i) => { tab.setAttribute('aria-selected', String(i === index)); tab.tabIndex = i === index ? 0 : -1; });
  picture.src = `assets/${images[index]}`;
  picture.alt = tabs[index].textContent;
  panel.setAttribute('aria-labelledby', tabs[index].id);
}
tabs.forEach((tab, index) => {
  tab.tabIndex = index === 0 ? 0 : -1;
  tab.addEventListener('click', () => select(index));
  tab.addEventListener('keydown', event => {
    const offset = event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : 0;
    if (!offset) return;
    event.preventDefault(); const next = (index + offset + tabs.length) % tabs.length;
    select(next); tabs[next].focus();
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
document.querySelector('#reset-orders').addEventListener('click', () => chooseOrder(0));
document.addEventListener('click', event => {
  if (!event.target.closest('.order-row')) orderRows.forEach(row => { row.classList.remove('is-expanded'); row.querySelector('.order-time').setAttribute('aria-expanded', 'false'); });
});
