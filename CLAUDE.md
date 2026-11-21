# CLAUDE.md – SoRalli (Godot 4)

## Projekti
Isometrinen 3D-rallipeli Godot 4.x:llä (uusin vakaa versio, **Forward+**-renderöijä). Kaikki vaatimukset ovat tiedostossa `SPEC.md`, ja näkymien kuvat kansiossa `mockups/`. Lue molemmat ennen kuin aloitat uuden vaiheen.

## Työtapa
- Tee **yksi vaihe kerrallaan** (SPEC.md § 8). Kerro lopuksi, miten vaiheen voi testata, ja commitoi `dev`-haaraan.
- Älä aloita seuraavaa vaihetta pyytämättä.
- Älä commitoi suoraan `master`iin. Se julkaisee pelin.
- Kysy ennen kuin lisäät addoneita tai ulkoisia riippuvuuksia.
- Tarkista muutosten jälkeen, että projekti latautuu: `godot --headless --quit`. Virheitä tai varoituksia ei saa jäädä.
- Mockupit ovat suuntaa antavia. Värit, fontit, sijoittelu ja tekstit noudattavat niitä, mutta mittojen ei tarvitse olla pikselintarkkoja.

## Koodityyli
- GDScript ja **staattinen tyypitys** kaikkialla (`var speed: float`, `func foo() -> void`).
- Tiedostot ja nodet snake_case, luokat (`class_name`) PascalCase. Koodi ja kommentit englanniksi, käyttöliittymän tekstit suomeksi.
- Säädettävät arvot ovat `@export`-muuttujia tai `Resource`-tiedostoja (CarStats, SurfaceData, EnvPreset). Ei taikanumeroita koodissa.
- Signaalit nodejen väliseen viestintään. Autoloadit vain globaalille tilalle (GameState, InputManager, Settings).
- Kaikki UI-tekstit `tr()`-funktion kautta, jotta käännös onnistuu myöhemmin.

## Grafiikan säännöt
- Low-poly-mallit tehdään koodilla tai yksinkertaisina meshinä (CSG tai ArrayMesh) siihen asti, kunnes oikeat mallit ovat käytettävissä. Tasavarjostus ja vertex-värit.
- Tekstuurit enintään 128×128. Retrotyylissä (oletus) ne pienennetään 32×32:een ja näytetään ilman suodatusta, Moderni-tyylissä suodatus on linear. Retrotyylin luvut ovat tiedostossa `env/retro_style.tres`.
- Valaistus, varjot, SSAO, glow, sumu ja tonemap asetetaan `WorldEnvironment`-esiasetuksiin. Sää ja vuorokaudenaika vaihtavat esiasetusta.

## Haarat ja julkaisu
Kaksi haaraa: `dev` ja `master`. Uusi työ tehdään `dev`-haaraan. `master` on viimeisin julkaistu versio.

Versio on `project.godot`-tiedostossa (`application/config/version`) ja näkyy päävalikossa. Pelaajalle näkyvät muutokset kirjataan `CHANGELOG.md`:n ylimpään kohtaan (`## [x.y.z] - julkaisematon`) sitä mukaa kuin niitä tehdään. Versiot: **pää** (1.0.0) rikkoo yhteensopivuuden, **sivu** (0.5.0) lisää ominaisuuksia, **korjaus** (0.5.1) on korjaus tai pieni hionta.

- `dev`-push buildaa pelin. Testibuildi (Windows ja macOS) on Actions-ajon artefakti 14 päivää.
- `master`-push buildaa saman ja julkaisee GitHub-releasen tagilla `v<versio>`. Muistiinpanot ovat muutoslokin kohdan runko.

Julkaisu `dev`-haarassa, sitten yhdistäminen `master`iin:

1. Vaihda ylimmän kohdan otsikko muotoon `## [x.y.z] - VVVV-KK-PP`. Pohjan linkki osoitetaan julkaisuun (`releases/tag/vx.y.z`), ei enää `dev`-vertailuun. Commitoi `Release x.y.z`. Versiota ei nosteta tässä commitissa: master julkaisee sen version, joka tiedostossa jo on.
2. Yhdistä commit `master`iin ja pushaa. Build keskeytyy, jos tagi `vx.y.z` on jo olemassa tai otsikosta puuttuu päivämäärä.
3. Jatka `dev`-haarassa: nosta `application/config/version`, lisää uusi `## [seuraava] - julkaisematon` ja vertailulinkki edelliseen tagiin. Commitoi `Open version seuraava`.

## Moninpeli
- Jaettu ruutu: yksi `World3D`, ja jokaisella pelaajalla oma `SubViewport`, `Camera3D` ja HUD.
- Syötteet erotellaan laitteen mukaan InputManagerissa. Pelaajan ohjauskoodi ei koskaan lue globaaleja `Input.is_action_pressed`-kutsuja suoraan, vaan pelaajakohtaisen syötteen.
