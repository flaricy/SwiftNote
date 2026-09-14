const tabs = [...document.querySelectorAll('[data-scene]')];
const picture = document.querySelector('#scene-image');
const panel = document.querySelector('#scene');
const images = ['editor.png', 'selection.png', 'dark.png'];
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
