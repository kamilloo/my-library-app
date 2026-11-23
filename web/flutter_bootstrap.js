{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load().catch(error => {
  console.error(error);
  document.querySelector('#startup').textContent =
    'Nie udało się uruchomić biblioteki. Połącz się z internetem i spróbuj ponownie.';
});
