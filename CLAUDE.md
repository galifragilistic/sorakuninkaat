# CLAUDE.md – Sorakuninkaat (Godot 4)

## Projekti
Isometrinen 3D-rallipeli Godot 4.x:llä (uusin vakaa versio, **Forward+**-renderöijä). Kaikki vaatimukset ovat tiedostossa `SPEC.md`, ja näkymien kuvat kansiossa `mockups/`. Lue molemmat ennen kuin aloitat uuden vaiheen.

## Työtapa
- Tee **yksi vaihe kerrallaan** (SPEC.md § 8). Kerro lopuksi, miten vaiheen voi testata, ja commitoi.
- Älä aloita seuraavaa vaihetta pyytämättä.
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
- Tekstuurit enintään 128×128, suodatus linear.
- Valaistus, varjot, SSAO, glow, sumu ja tonemap asetetaan `WorldEnvironment`-esiasetuksiin. Sää ja vuorokaudenaika vaihtavat esiasetusta.

## Moninpeli
- Jaettu ruutu: yksi `World3D`, ja jokaisella pelaajalla oma `SubViewport`, `Camera3D` ja HUD.
- Syötteet erotellaan laitteen mukaan InputManagerissa. Pelaajan ohjauskoodi ei koskaan lue globaaleja `Input.is_action_pressed`-kutsuja suoraan, vaan pelaajakohtaisen syötteen.
