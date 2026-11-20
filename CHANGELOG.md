# Muutosloki

Kaikki pelaajalle näkyvät muutokset kirjataan tähän. Versiot noudattavat [semanttista versiointia](https://semver.org/lang/fi/):

- **pää** (1.0.0): iso kokonaisuus tai yhteensopimattomat muutokset (esim. tallennetut radat tai verkkopeli vanhan version kanssa eivät enää toimi)
- **sivu** (0.3.0): uusia ominaisuuksia
- **korjaus** (0.2.1): korjauksia ja pieniä hiontoja

Versio on tiedostossa `project.godot` (`application/config/version`). Ylin kohta kertoo seuraavan version, ja siihen lisätään muutokset sitä mukaa kuin niitä tehdään `dev`-haaraan. Ennen kuin `dev` yhdistetään `master`iin, otsikon *julkaisematon* vaihdetaan julkaisupäiväksi. Master-build julkaisee version tagilla `v<versio>` ja tämän kohdan release-muistiinpanoina.

## [0.4.0] - 2026-11-20

### Muutettu
- Verkkopelin isäntä näkee julkisen IP-osoitteensa, johon muut voivat liittyä internetin yli. Lähiverkkopelissä näkyy edelleen paikallinen osoite.
- Verkkopelistä poistuminen kysyy vahvistuksen.
- Moninpeliaulassa kohdistin liikkuu vain pelaajalla 1 (verkossa isännällä), eikä se mene muiden pelaajien korteille. Muut pelaajat ohjaavat vain omaa korttiaan.
- Oma kortti kertoo, mitä A-nappi tekee seuraavaksi (valitse auto, valmis, vaihda autoa). Autovalintaan siirtyminen poistaa valmis-tilan, kunnes auto on vahvistettu.

### Korjattu
- Verkkopelissä autojen väliset törmäykset eivät enää nyi asiakkaalla, eivätkä autot mene toistensa sisään.
- Pitkä auton nimi (Vanha Valtias) ei enää vuoda pelaajakortin yli.
- Pelaajakortin värillinen yläreuna seuraa kortin viistettyä kulmaa.
- Asiakkaan aulasta poistettiin turha *Yhdistetty isäntään* -teksti.

## [0.3.1] - 2026-11-19

### Muutettu
- Päävalikon versionumero on siirretty oikeaan alanurkkaan.

## [0.3.0] - 2026-11-19

### Lisätty
- Muutosloki ja versionumero. Versio näkyy päävalikossa, ja jokaisen julkaisun muutokset näkyvät Releases-sivulla.

## [0.2.1] - 2026-11-19

### Muutettu
- README esittelee Retro-tyylin, kielivalinnan, maaston varjostuksen, uudet maisemamallit ja palautussäännöt.

*Julkaistu tagilla `v2026.11.19-13`.*

## [0.2.0] - 2026-11-18

### Lisätty
- **Grafiikkatyyli:** oletuksena Retro (PS1/N64-henkinen: matala resoluutio, terävät pikselit, 15-bittiset värit ditheröinnillä ja 32×32-tekstuurit). Moderni-tyyli säilyttää aiemman ilmeen.
- Retro-tyylissä valikot ja HUD käyttävät pikselifonttia.
- **Kieli:** englanti suomen rinnalle (*Asetukset → Kieli / Language*). Suomi on edelleen oletus.
- Maaston rinnevarjostus ja korkeuskäyrät, jotka erottavat loivatkin mäet isometrisestä kamerasta.
- Blenderillä tehdyt low-poly-maisemamallit: kuuset, männyt, koivut ja niiden lumiset versiot, heinäpaalit, kontit, punainen talo, kivet ja rengaspinot.
- Ohitetusta portista tulee varoitus *PALAA PORTILLE*, ja portti vilkkuu oranssina, kunnes sen läpi ajetaan.

### Muutettu
- Tielle palautus toimii vain, kun auto on tieltä suistunut tai kumollaan, ja se vie auton 10 m taaksepäin. Mutkaa ei voi enää oikaista palautuksella.

*Julkaistu tagilla `v2026.11.18-11`.*

## [0.1.1] - 2026-11-18

### Muutettu
- README: kuvakaappaukset, latausohjeet, ominaisuudet ja ohjaimet.

*Julkaistu tagilla `v2026.11.18-4`.*

## [0.1.0] - 2026-11-18

Ensimmäinen julkaisu.

### Lisätty
- Kuusi rataa soralla, hiekalla, jäällä, asfaltilla ja lumessa: mäkiä, notkoja, siltoja, tunneleita ja hyppyreitä.
- Kuusi Blenderillä mallinnettua autoa omine ominaisuuksineen, väreineen ja kuvioineen. Kilpanumeron voi sijoittaa kylkeen, katolle tai konepellille.
- Sää ja vuorokaudenaika: aamu, päivä, ilta ja yö sekä aurinko, sade, lumisade ja sumu.
- Jaettu ruutu 1–4 pelaajalle näppäimistöillä ja ohjaimilla. Tyhjille paikoille tulevat tekoälykuskit.
- Verkkopeli lähiverkossa tai suoralla IP-osoitteella, ja asiakkaat ennustavat oman autonsa liikkeen.
- Moninpeliaula: pelaaja 1 valitsee kisan asetukset, ja muut valitsevat autonsa ja nimensä itse.
- Rataeditori: piirrä rata, säädä korkeudet, lisää sillat, tunnelit, hyppyrit ja maisema, kumoa ja tee uudelleen, ja koeaja heti.
- Väliajat ja näkyvät tarkistusportit, minikartta, vauriot, kierroslukua ja vaihteita seuraava moottorin ääni sekä alustan mukaan vaihtuvat renkaiden äänet.
- Suuntaohjaus valittavissa autovalinnassa.
- Painikevihjeet vaihtuvat käytössä olevan laitteen mukaan.
- Windows- ja macOS-buildit.

[0.4.0]: https://github.com/galifragilistic/sorakuninkaat/releases/tag/v0.4.0
[0.3.1]: https://github.com/galifragilistic/sorakuninkaat/releases/tag/v0.3.1
[0.3.0]: https://github.com/galifragilistic/sorakuninkaat/releases/tag/v0.3.0
[0.2.1]: https://github.com/galifragilistic/sorakuninkaat/releases/tag/v2026.11.19-13
[0.2.0]: https://github.com/galifragilistic/sorakuninkaat/releases/tag/v2026.11.18-11
[0.1.1]: https://github.com/galifragilistic/sorakuninkaat/releases/tag/v2026.11.18-4
[0.1.0]: https://github.com/galifragilistic/sorakuninkaat/releases/tag/v2026.11.18-2
