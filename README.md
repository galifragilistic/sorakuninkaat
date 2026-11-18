# SoRalli

Isometrinen rallipeli 1–4 pelaajalle samalla sohvalla tai verkossa. Lyhyitä ratoja, soraa, hyppyjä ja sladeja 90-luvun ylhäältä kuvattujen rallipelien hengessä: low-poly-grafiikka ja moderni valaistus.

![Neljä autoa Soramontun mutkassa](docs/screenshots/hero.jpg)

## Lataa

Uusin versio löytyy [Releases-sivulta](https://github.com/galifragilistic/sorakuninkaat/releases/latest):

- **Windows:** `SoRalli-Windows.zip`. Pura ja käynnistä `SoRalli.exe`. Jos SmartScreen varoittaa, valitse *Lisätietoja → Suorita silti*.
- **macOS** (Apple Silicon ja Intel): `SoRalli-macOS.zip`. Pura ja avaa `SoRalli.app` ensimmäisellä kerralla hiiren oikealla painikkeella → *Avaa*, koska sovellusta ei ole notarisoitu.

## Ominaisuudet

- **Kuusi rataa** soralla, hiekalla, jäällä, asfaltilla ja lumessa, mäkineen, siltoineen, tunneleineen ja hyppyreineen
- **Kuusi autoa** omilla ominaisuuksillaan, väreillä, kuvioilla ja kilpanumerolla kyljessä, katolla tai konepellillä
- **Sää ja vuorokaudenaika:** aamu, päivä, ilta ja yö sekä aurinko, sade, lumisade ja sumu
- **Jaettu ruutu 1–4 pelaajalle** näppäimistöillä ja ohjaimilla, tyhjille paikoille tekoälykuskit
- **Verkkopeli** lähiverkossa tai suoralla IP-osoitteella
- **Rataeditori:** piirrä oma rata, säädä korkeudet, lisää sillat, tunnelit, hyppyrit ja maisema, ja koeaja heti
- Vauriot, väliajat, minikartta, moottori- ja renkaiden äänet

## Kuvia

| | |
|---|---|
| ![Ilta-ajo sateessa sillalla](docs/screenshots/race_rain.jpg) | ![Lumisade Tunturilla](docs/screenshots/race_snow.jpg) |
| ![Yö satamassa ajovalojen loisteessa](docs/screenshots/race_night.jpg) | ![Kahden pelaajan jaettu ruutu](docs/screenshots/split_screen.jpg) |
| ![Neljä pelaajaa Jäisellä järvellä](docs/screenshots/four_players.jpg) | ![Moninpeliaula](docs/screenshots/lobby.jpg) |
| ![Päävalikko](docs/screenshots/menu.jpg) | ![Auton valinta](docs/screenshots/car_select.jpg) |

![Rataeditori](docs/screenshots/track_editor.jpg)

## Ohjaimet

| | P1 (WASD) | P2 (nuolet) | Ohjain |
|---|---|---|---|
| Kaasu / jarru | W / S | ▲ / ▼ | RT / LT |
| Ohjaus | A / D | ◀ / ▶ | Vasen tikku |
| Käsijarru | Välilyönti | Oikea Shift | X |
| Takaisin tielle | R | Enter | Back |
| Tauko | Esc | Esc | Start |

Moninpeliaulassa pelaaja 1 valitsee kisan asetukset. Muut liittyvät ja hyväksyvät autonsa omalla käsijarrunapillaan (oikea Shift tai ohjaimen A): vasen ja oikea vaihtavat autoa, ylös ja alas väriä.

## Kehitys

Peli on tehty [Godot 4.7](https://godotengine.org):llä (Forward+). Avaa kansio Godotissa ja käynnistä F5:llä.

- [`SPEC.md`](SPEC.md): pelin määrittely ja tila
- [`CLAUDE.md`](CLAUDE.md): koodityyli ja työtavat
- `mockups/`: näkymien alkuperäiset suunnitelmat
- `tools/blender/build_cars.py`: automallit, rakennetaan Blenderillä (`blender --background --factory-startup --python tools/blender/build_cars.py -- .`)

**Haarat ja julkaisut:** uudet muutokset tehdään `dev`-haaraan. Jokaisesta devin pushista GitHub Actions tekee testattavat Windows- ja Mac-buildit (Actions-välilehti → ajon artefaktit). Kun muutokset on testattu, dev yhdistetään `master`iin, ja siitä syntyy automaattisesti uusi release.

Buildin voi tehdä myös itse:

```bash
godot --headless --export-release "macOS" build/macos/SoRalli.app
godot --headless --export-release "Windows Desktop" build/windows/SoRalli.exe
```

Fontit Russo One ja Chakra Petch ovat OFL-lisenssillä (`assets/fonts/`).
