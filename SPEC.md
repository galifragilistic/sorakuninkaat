# SoRalli – pelin määrittely

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
- Tekstuurit 64×64–128×128 (retrotyylissä 32×32 ilman suodatusta, ks. alla). Paljon pelkkiä vertex-värejä.
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
- Partikkelit (`GPUParticles3D`): renkaiden pölypilvet, joiden määrä ja väri tulevat alustasta (sora, hiekka, lumi, vesi), pöly laskeutumisissa sekä sade ja lumisade. Kipinät kolareissa ja omat roisketehosteet: ks. § 10.
- Sää- ja aikavariaatiot: Aamu, Päivä, Ilta (iltarusko), Yö sekä Aurinko, Sade, Lumi, Sumu. Toteutetaan esiasetuksina (environment + valo).
- Laatuasetukset: Matala, Keski ja Korkea. Matalalla pois SSAO, volumetric ja SSIL.

### Grafiikkatyyli: Retro (oletus) tai Moderni
Retrotyyli jäljittelee PS1- ja N64-konsoleita (`env/retro_style.tres`, `util/retro.gd`):
- 3D-kuva renderöidään pienellä tarkkuudella (koko ruudun näkymä 270 riviä) ja suurennetaan teräväreunaisin pikselein. Ei reunanpehmennystä.
- Värit pudotetaan 15-bittisiksi (5 bittiä kanavaa kohden) ja väliin tulee 4×4 Bayer -ditherointi.
- Maan ja teiden tekstuurit pienennetään 32×32:een ja näytetään ilman suodatusta.
- HUD ja valikot piirretään suunnittelutarkkuudella 1280×720 ja suurennetaan ruudulle, joten isolla näytöllä nekin näkyvät isoina pikseleinä. Tekstit käyttävät koodilla piirrettyä bittikarttafonttia (16-bit-henkinen 5×7-pikselifontti, lihavoitu versio otsikoille ja napeille), jonka pikselit ovat kokonaislukumonikertoja (fonttikoot 13–19 → 2×2, 20–27 → 3×3 jne.). Valikoiden 3D-esikatselut noudattavat samaa tyyliä.

Moderni-tyyli on aiempi ilme: täysi tarkkuus, MSAA ja suodatetut tekstuurit.

## 3. Ajaminen

- Arcade-tyylinen ajettavuus, ei simulaatio. Sladitus kuuluu asiaan.
- Suositus: oma `RigidBody3D` ja raycast-jousitus (4 sädettä), ei `VehicleBody3D`. Näin luisto ja pito ovat helpommin hallittavissa.
- Alustat ja niiden pitokertoimet säädetään datasta:
  - Asfaltti 1,0
  - Sora 0,75
  - Hiekka 0,65
  - Lumi 0,5
  - Jää 0,3

  Tien ulkopuolisilla pinnoilla on omat arvonsa: betoni 0,9, nurmi 0,6, dyyni 0,55, vesi 0,5 ja hanki 0,45.
- Radoilla on korkeuseroja: mäkiä, notkoja, siltoja ja tunneleita. Maasto seuraa tien reunaa ilman korkeita portaita.
- Hypyt: ilmassa ohjaus on rajattu, ja laskeutuminen näkyy jousituksessa ja pölyssä.
- Vauriot: neljä aluetta (etu, keski, taka, renkaat). Vaurio heikentää huippunopeutta tai ohjausta. Voi kytkeä pois päältä.
- Autojen ominaisuudet (1–10) tulevat `Resource`-tiedostoista: huippunopeus, kiihtyvyys, pito soralla, pito asfaltilla ja kestävyys. Lisäksi vetotapa (FWD, RWD tai 4WD).

## 4. Pelitilat ja moninpeli

- **Yksinpeli:** yksittäinen kisa tekoälykuskeja vastaan. Pisteet kertyvät pelikerran ajan. Mestaruus, aika-ajo ja harjoitus: ks. § 10.
- **Moninpeli, jaettu ruutu 1–4 pelaajaa** (ensisijainen):
  - Jokaisella pelaajalla on oma `SubViewport` ja kamera, ja kaikki jakavat saman `World3D`:n.
  - Asettelut:
    - 1 pelaaja: koko ruutu
    - 2 pelaajaa: pystyjako (oletus) tai vaakajako
    - 3 pelaajaa: kaksi ylhäällä ja yksi alhaalla tai 2×2, jossa yksi ruutu näyttää minikartan
    - 4 pelaajaa: 2×2
  - Ohjaimet: P1 näppäimistö (WASD), P2 näppäimistö (nuolet) tai ohjain. Ohjaimet liitetään aulassa A-painikkeella. Jokaisen pelaajan syöte erotellaan laitteen mukaan. Painikevihjeet vaihtuvat käytössä olevan laitteen mukaan.
  - Pelaajat voivat antaa itselleen nimen aulassa.
  - Tyhjät paikat voi täyttää tekoälykuskeilla, jotka seuraavat radan keskilinjaa (`Curve3D`), hidastavat mutkiin ja palautuvat jumista.
- **Verkko:** Godotin high-level multiplayer (ENet), lähiverkko (automaattinen haku) ja suora IP. Palvelinarkkitehtuuri: isäntä omistaa aulan ja simuloi kisan, ja jokaisella koneella on yksi pelaaja. Asiakas lähettää syötteensä, ennustaa oman autonsa liikkeen ja näyttää muut autot interpoloituna isännän tilannekuvista. Jos pelaaja poistuu kesken, paikka ei siirry tekoälylle.

## 5. Näkymät ja siirtymät

```
Päävalikko ─┬─ Yksinpeli → Auton valinta → Radan valinta → Kisa → Tulokset
            ├─ Moninpeli → Aula ⇄ Auton valinta / Radan valinta → Kisa (jaettu ruutu) → Tulokset
            ├─ Autotalli → Auton valinta
            ├─ Radat → Radan valinta
            ├─ Rataeditori → Koeajo
            ├─ Asetukset (grafiikkatyyli, grafiikan laatu, koko ruutu, äänenvoimakkuus, vauriot, kieli)
            └─ Lopeta
Tulokset → Uusintakisa | Vaihda rata | Aulaan (yksinpelissä Valikkoon)
Kisa → Tauko (Jatka, Aloita alusta, Asetukset, Lopeta kisa)
```

| # | Kuva | Sisältö |
|---|------|---------|
| 1 | `01_Main.png` | Logo, valikko (valittu kohta täysvärinen ja leveämpi, alla alaotsikko), ohjainten tila P1–P4. Viikon haaste: ks. § 10. Taustalla elävä pelimaailma, jossa autot ajavat. |
| 2 | `02_Moninpeli.png` | Välilehdet (Jaettu ruutu, Lähiverkko, Verkko), 4 pelaajakorttia (väri, auto, laite, tila VALMIS / VALITSEE AUTOA / tyhjä paikka), kisan asetukset (rata, kierrokset, sää, aika, vauriot, ruudunjako), ALOITA KISA. |
| 3 | `03_Autovalinta.png` | Autolista ja luokat, auto pyörivällä alustalla kohdevalossa, ominaisuuspalkit (10 palaa), 8 väriä, kuvio. |
| 4 | `04_Ratavalinta.png` | Alustasuodattimet, ratakortit (pohjakuva, alusta, pituus), esikatselu sekä sään ja vuorokaudenajan valinta, ratatietue. |
| 5 | `05_Peli.png` | HUD: sija ja kierros, sijoituslista, kierrosaika ja paras aika, väliaika-ilmoitus, minikartta, vauriot, nopeusmittari ja vaihde. Muiden autojen yllä P-tunnisteet. |
| 6 | `06_Jaettu.png` | Kahden pelaajan pystyjako. Jokaisella oma värikehys ja kompakti HUD. Minikartta on yhteinen keskellä ylhäällä, ohitusilmoitukset keskellä alhaalla. |
| 7 | `07_Tulokset.png` | Palkintokoroke, tulostaulukko (aika, paras kierros, NOPEIN-merkki, pisteet), toiminnot. Taustalla sumennettu pelinäkymä. |
| 8 | `08_Tyyliopas.png` | Värit, fontit, komponentit ja grafiikan periaatteet. |
| – | (ei kuvaa) | Rataeditori: kartta, korkeusprofiili ja sivupaneeli. Tehty samalla tyylillä kuin muut näkymät. |

### Rataeditori
- Suljettu tie piirretään kartalle ohjauspisteillä (enintään 40). Pisteen korkeutta säädetään rullalla, ja korkeusprofiili näkyy kartan alla.
- Tieosuuksille voi merkitä sillan, tunnelin tai hyppyrin. Kun tie kulkee toisen yli riittävän korkealla, risteykseen tulee silta automaattisesti. Liian matalasta risteyksestä tulee varoitus.
- Säädettävissä ovat radan nimi, maasto (teema), karttakoko (Pieni, Normaali, Suuri, Valtava), tien leveys, tieosuuksien pinta (teeman mukaan, asfaltti, sora, hiekka, lumi tai jää), puusto ja lähtöpiste. Ajosuunnan voi kääntää.
- Esineitä (puu, paali, kontti, talo, kivi, rengaspino) voi sijoittaa, siirtää ja kiertää käsin.
- Korotettu tie nostaa maastoa ja laskettu tie laskee sitä.
- Radat tallennetaan kansioon `user://tracks`, ja keskeneräinen rata säilyy luonnoksena. Radan voi koeajaa suoraan editorista, ja tallennetut radat näkyvät radan valinnassa.

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

  Lisäksi pelaajan rataeditorilla tekemät radat. Peilatut radat: ks. § 10.
- **Autojen ulkonäkö:** jokaisella autolla on oma korinmuoto (spoileri, valot ym.), ja maalikuvioita on useita.
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

Vaiheet 1–7 ovat valmiit. Niiden jälkeen on lisätty:
- korkeuserot, sillat ja tunnelit sekä näkyvät checkpointit
- pelaajien nimet aulassa ja laitteen mukaan vaihtuvat painikevihjeet
- autojen omat korinmuodot ja lisää maalikuvioita
- rataeditori (§ 5)
- verkkopelin asiakaspuolen ennustus
- Windows-vientiasetus

## 9. Projektirakenne

```
res://
  autoload/      game_state.gd, input_manager.gd, settings.gd, network.gd,
                 player_input.gd, player_setup.gd
  audio/         sound_bank.gd
  cars/          car.tscn, car.gd, ai_driver.gd, car_damage.gd, data/*.tres (CarStats)
  data/          catalog.gd (valikoiden autot, radat, värit, pisteet)
  tracks/        soramonttu/…, track.gd, checkpoint.gd, track_design.gd,
                 custom_tracks.gd, surfaces/*.tres, themes/*.tres
  race/          race_manager.gd, split_screen.tscn, camera_rig.gd, net_sync.gd
  ui/            theme.tres, menus/*.tscn, hud/*.tscn, editor/*, shaders/panel.gdshader
  env/           presets/*.tres (aika), weather/*.tres (sää), shaders/vignette.gdshader
  vfx/           dust.tscn, precipitation.gd
  util/          low_poly.gd
  tools/         build_theme.gd
  assets/fonts/  (mukana)
```

## 10. Myöhemmin (ei vielä toteutettu)

- Yksinpelin tilat: mestaruus (sarja ratoja ja pisteet), aika-ajo haamuautolla ja harjoitus.
- Kaikkien ratojen ajaminen peilattuina.
- Päävalikon viikon haaste.
- Ohjainasetukset (näppäinten ja ohjainpainikkeiden vaihto).
- Kipinät kolareissa ja omat roisketehosteet vedelle ja lumelle.
- 6 lukittua autoa ovat vasta paikkoja listassa. Varsinaiset autot ja avaustapa puuttuvat.
