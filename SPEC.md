# Sorakuninkaat – pelin määrittely

Isometrinen 3D-rallipeli Godot 4:llä. Henkeä haetaan 90-luvun ylhäältä kuvatuista rallipeleistä: lyhyet radat, sora, hypyt ja kaverit samalla sohvalla. **Geometria ja tekstuurit ovat N64-tasoa, valaistus ja jälkikäsittely modernia.**

Näkymien kuvat ovat kansiossa `mockups/` (PNG 2560×1440, suunniteltu 1280×720-koossa). HTML-versiot ovat kansiossa `mockups/html/`, josta voi lukea tarkat värit, koot ja tekstit. Kuvat ovat suuntaa antavia, eivät pikselintarkkoja.

---

## 1. Kamera

- `Camera3D`, projektio **orthogonal**.
- Isometrinen kulma: yaw 45°, pitch noin −35° (säädettävä välillä −30° … −45°, jotta tuntumaa voi hioa).
- Seuraa pelaajan autoa pehmeästi (lerp/jousi). Lisää ennakointi auton nopeuden suuntaan, jotta edessä oleva tie näkyy paremmin.
- Zoomaa hieman ulos suurella nopeudella (orthogonal `size` +10–15 %).
- Kamera ei pyöri auton mukana. Maailma pysyy aina samassa kulmassa.

## 2. Grafiikka

### N64-tason geometria ja tekstuurit
- Autossa 300–800 kolmiota, puissa ja esineissä 20–100.
- Tasavarjostettu low-poly: puissa ja maassa selvästi näkyvät kolmiot ja kaksisävyinen varjostus (valoisa ja varjoisa puoli).
- Tekstuurit 64×64–128×128, bilineaarinen suodatus (ei pikseligrafiikkaa). Paljon pelkkiä vertex-värejä.
- Ei normal mappeja. Materiaaleissa enintään roughness ja metallic.
- Maasto on kolmioista koottu ruudukko, jonka laikut ovat hieman eri sävyisiä (ks. `05_Peli.png`).

### Moderni valaistus (Forward+ -renderöijä)
- `DirectionalLight3D`: matala iltaruskon aurinko vasemmalta ylhäältä. Pitkät, pehmeät varjot (soft shadows, PCSS).
- `WorldEnvironment`:
  - SSAO ja kontaktivarjot autojen ja puiden alla
  - SSIL tai SDFGI valinnaisena, laatuasetuksen takana
  - Glow (bloom) lampuille, ajovaloille ja kirkkaille pinnoille
  - Volumetrinen sumu, jossa näkyvät auringonsäteet
  - Tonemap ACES (tai AgX), lämmin/kylmä värisävytys
  - Vinjetti post-process-shaderilla
- Ajovalot ovat `SpotLight3D`-valoja, ja keila näkyy maassa. Lisäksi pienet emissiiviset lisävalot keulassa.
- Ratavalot ovat `OmniLight3D`-valoja, joilla on lämmin valolammikko maassa ja lens flare -juova.
- Partikkelit (`GPUParticles3D`): pölypilvet sorassa, roiskeet vedessä ja lumessa sekä kipinät kolareissa.
- Sää- ja aikavariaatiot: Aamu, Päivä, Ilta (iltarusko), Yö sekä Aurinko, Sade, Lumi, Sumu. Toteutetaan esiasetuksina (environment + valo).
- Laatuasetukset: Matala, Keski ja Korkea. Matalalla pois SSAO, volumetric ja SSIL.

## 3. Ajaminen

- Arcade-tyylinen ajettavuus, ei simulaatio. Sladitus kuuluu asiaan.
- Suositus: oma `RigidBody3D` ja raycast-jousitus (4 sädettä), ei `VehicleBody3D`. Näin luisto ja pito ovat helpommin hallittavissa.
- Alustat ja niiden pitokertoimet säädetään datasta:
  - Asfaltti 1,0
  - Sora 0,75
  - Hiekka 0,65
  - Lumi 0,5
  - Jää 0,3
- Hypyt: ilmassa ohjaus on rajattu, ja laskeutuminen näkyy jousituksessa ja pölyssä.
- Vauriot: neljä aluetta (etu, keski, taka, renkaat). Vaurio heikentää huippunopeutta tai ohjausta. Voi kytkeä pois päältä.
- Autojen ominaisuudet (1–10) tulevat `Resource`-tiedostoista: huippunopeus, kiihtyvyys, pito soralla, pito asfaltilla ja kestävyys. Lisäksi vetotapa (FWD, RWD tai 4WD).

## 4. Pelitilat ja moninpeli

- **Yksinpeli:** mestaruus (sarja ratoja ja pisteet), aika-ajo (haamuauto) ja harjoitus.
- **Moninpeli, jaettu ruutu 1–4 pelaajaa** (ensisijainen):
  - Jokaisella pelaajalla on oma `SubViewport` ja kamera, ja kaikki jakavat saman `World3D`:n.
  - Asettelut:
    - 1 pelaaja: koko ruutu
    - 2 pelaajaa: pystyjako (oletus) tai vaakajako
    - 3 pelaajaa: kaksi ylhäällä ja yksi alhaalla tai 2×2, jossa yksi ruutu näyttää minikartan
    - 4 pelaajaa: 2×2
  - Ohjaimet: P1 näppäimistö (WASD), P2 näppäimistö (nuolet) tai ohjain. Ohjaimet liitetään aulassa A-painikkeella. Jokaisen pelaajan syöte erotellaan laitteen mukaan.
  - Tyhjät paikat voi täyttää tekoälykuskeilla, jotka seuraavat rataa `Path3D`-reitin perusteella.
- **Verkko** (myöhemmin): Godotin high-level multiplayer (ENet). Lähiverkko ja suora IP, palvelinarkkitehtuuri. Aulan välilehdet ovat jo valmiina UI:ssa.

## 5. Näkymät ja siirtymät

```
Päävalikko ─┬─ Yksinpeli → Auton valinta → Radan valinta → Kisa → Tulokset
            ├─ Moninpeli → Aula ⇄ Auton valinta / Radan valinta → Kisa (jaettu ruutu) → Tulokset
            ├─ Autotalli → Auton valinta
            ├─ Radat → Radan valinta
            ├─ Asetukset (grafiikka, ääni, ohjaimet)
            └─ Lopeta
Tulokset → Uusintakisa | Vaihda rata | Aulaan
Kisa → Tauko (Jatka, Aloita alusta, Asetukset, Lopeta kisa)
```

| # | Kuva | Sisältö |
|---|------|---------|
| 1 | `01_Main.png` | Logo, valikko (valittu kohta täysvärinen ja leveämpi, alla alaotsikko), ohjainten tila P1–P4, viikon haaste. Taustalla elävä pelimaailma, jossa autot ajavat. |
| 2 | `02_Moninpeli.png` | Välilehdet (Jaettu ruutu, Lähiverkko, Verkko), 4 pelaajakorttia (väri, auto, laite, tila VALMIS / VALITSEE AUTOA / tyhjä paikka), kisan asetukset (rata, kierrokset, sää, aika, vauriot, ruudunjako), ALOITA KISA. |
| 3 | `03_Autovalinta.png` | Autolista ja luokat, auto pyörivällä alustalla kohdevalossa, ominaisuuspalkit (10 palaa), 8 väriä, kuvio. |
| 4 | `04_Ratavalinta.png` | Alustasuodattimet, ratakortit (pohjakuva, alusta, pituus), esikatselu sekä sään ja vuorokaudenajan valinta, ratatietue. |
| 5 | `05_Peli.png` | HUD: sija ja kierros, sijoituslista, kierrosaika ja paras aika, väliaika-ilmoitus, minikartta, vauriot, nopeusmittari ja vaihde. Muiden autojen yllä P-tunnisteet. |
| 6 | `06_Jaettu.png` | Kahden pelaajan pystyjako. Jokaisella oma värikehys ja kompakti HUD. Minikartta on yhteinen keskellä ylhäällä, ohitusilmoitukset keskellä alhaalla. |
| 7 | `07_Tulokset.png` | Palkintokoroke, tulostaulukko (aika, paras kierros, NOPEIN-merkki, pisteet), toiminnot. Taustalla sumennettu pelinäkymä. |
| 8 | `08_Tyyliopas.png` | Värit, fontit, komponentit ja grafiikan periaatteet. |

UI ohjataan kokonaan ohjaimella ja näppäimistöllä (focus-navigointi). Hiiri toimii myös.

## 6. UI-tyyli

- **Värit**

  | Rooli | Arvo |
  |-------|------|
  | Pohja | `#0E1220` |
  | Paneeli | `rgba(14,18,32,.86)` |
  | Viiva | `#2E3654` |
  | Teksti | `#F2F4FA` |
  | Toissijainen teksti | `#A3ACC7` |
  | Korostus | `#FF7A1A` (oranssi) |
  | Info | `#3FD8FF` (syaani) |

- **Pelaajavärit:** P1 `#FF7A1A`, P2 `#3FD8FF`, P3 `#B6F03C`, P4 `#FF4FA3`. Näitä käytetään auton väreinä, P-tunnisteissa, minikartan pisteissä ja jaetun ruudun kehyksissä.
- **Fontit** (mukana kansiossa `assets/fonts/`, OFL-lisenssi):
  - **Russo One**: otsikot, numerot ja painikkeet. Otsikot kursivoidaan −6° (skew).
  - **Chakra Petch** 400–700: muu teksti.
- **Paneelit:** 14 px viistetyt kulmat (oikea ylä ja vasen ala), 2 px reunaviiva, taustasumennus pelinäkymän päällä. Godotissa `StyleBoxFlat` ei tee viistoa kulmaa, joten käytetään omaa shaderia tai `NinePatchRect`-tekstuuria.
- **Valittu tila:** koko elementti täysvärinen (oranssi, teksti `#10131F`). Pelkkä reunaviiva ei riitä.
- **Teema:** kaikki tyylit kootaan yhteen `res://ui/theme.tres`-tiedostoon.
- **Resoluutio:** suunniteltu 1280×720-koossa, stretch mode `canvas_items`, aspect `expand`. Pienin teksti 13 px (1080p:ssä 20 px).

## 7. Sisältö (paikkatäytteitä, muutettavissa)

- **Autot:**

  | Auto | Luokka |
  |------|--------|
  | Kuplakone | C |
  | Pikku-Turbo | C |
  | Sora GT | B |
  | Hirvi 4x4 | B |
  | Lumikko | A |
  | Vanha Valtias | A |

  Lisäksi 6 lukittua autoa.
- **Radat:**

  | Rata | Alusta |
  |------|--------|
  | Soramonttu | sora, järvi ja hyppyri, iltarusko |
  | Hiekkasärkkä | hiekka |
  | Jäinen järvi | jää, kasiminen rata |
  | Metsäpolku | sora |
  | Satamakaarre | asfaltti |
  | Tunturi | lumi |

  Kaikki radat voi ajaa myös peilattuina.
- **Pisteet:** 10, 8, 6 ja 5 sijoituksille 1–4.

## 8. Toteutusvaiheet

Jokainen vaihe tehdään valmiiksi, ajetaan ja commitoidaan ennen seuraavaa.

1. **Ajettava prototyyppi:**
   - harmaalaatikkorata (Soramonttu) ja yksi auto
   - ortografinen isometrinen kamera, joka seuraa autoa
   - raycast-ajofysiikka sekä soran ja asfaltin pito
   - *Valmis, kun:* autolla voi sladittaa radan ympäri ja kamera tuntuu hyvältä.
2. **Ulkoasu ja valaistus:**
   - low-poly-maasto, puut ja järvi
   - iltaruskon valaistus, varjot, SSAO, glow, sumu
   - ajovalot, ratavalot ja pölypartikkelit
   - *Valmis, kun:* näkymä muistuttaa kuvaa `05_Peli.png`.
3. **Kisalogiikka ja HUD:** kierrokset, checkpointit, sijoitukset, ajat ja väliajat, minikartta, nopeusmittari ja vauriot.
4. **Jaettu ruutu 2 pelaajalle:** SubViewportit, syötteet laitteen mukaan, oma HUD kummallekin (`06_Jaettu.png`).
5. **Valikot:** teema, päävalikko, aula, auton ja radan valinta, tulokset sekä tauko. Täysi navigointi ohjaimella.
6. **Laajennukset:** 3–4 pelaajaa, tekoälykuskit, lisää autoja ja ratoja, sää ja vuorokaudenajat, vauriot ja hypyt, äänet.
7. **Verkkopeli:** ENet ja aulan Lähiverkko- ja Verkko-välilehdet.

## 9. Ehdotettu projektirakenne

```
res://
  autoload/      GameState.gd, InputManager.gd, Settings.gd
  cars/          car.tscn, car.gd, data/*.tres (CarStats)
  tracks/        soramonttu/…, track.gd, checkpoint.gd
  race/          race_manager.gd, split_screen.tscn, camera_rig.gd
  ui/            theme.tres, menus/*.tscn, hud/*.tscn, shaders/panel.gdshader
  env/           presets/*.tres (WorldEnvironment-, sää- ja aikaesiasetukset)
  vfx/           dust.tscn, splash.tscn
  assets/fonts/  (mukana)
```
