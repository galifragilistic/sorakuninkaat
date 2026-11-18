# SoRalli – toteutuspaketti Claude Codelle

**Sisältö**
- `SPEC.md`: pelin määrittely (kamera, grafiikka, ajaminen, moninpeli, näkymät, UI-tyyli, vaiheet)
- `CLAUDE.md`: pysyvät ohjeet, jotka Claude Code lukee automaattisesti
- `mockups/`: 8 näkymän kuvat (PNG) ja `mockups/html/`, jossa näkyvät tarkat värit ja tekstit
- `assets/fonts/`: Russo One ja Chakra Petch (OFL-lisenssi)

## Näin pääset alkuun
1. Asenna Godot 4 (uusin vakaa) ja varmista, että `godot` toimii komentoriviltä.
2. Pura paketti tyhjään kansioon ja aja siellä `git init`.
3. Avaa kansiossa Claude Code ja anna ensimmäiseksi kehotteeksi:

> Lue CLAUDE.md, SPEC.md ja kuvat mockups-kansiosta. Luo Godot 4 -projekti (Forward+) SPEC.md:n § 9 rakenteella ja toteuta vaihe 1: harmaalaatikkorata, yksi auto raycast-fysiikalla ja ortografinen isometrinen seurantakamera. Kerro lopuksi, miten testaan, ja commitoi.

4. Testaa Godotissa (F5). Anna palautetta ajotuntumasta ennen kuin siirryt eteenpäin, esimerkiksi: "Liikaa luistoa soralla, kamera saa ennakoida enemmän."
5. Jatka vaihe kerrallaan: *"Toteuta vaihe 2 SPEC.md:stä. Vertaa lopputulosta kuvaan mockups/05_Peli.png."*

**Vinkki:** valikkovaiheessa (5) kannattaa liittää kehotteeseen kyseinen kuva, esimerkiksi *"Tee aula kuvan mockups/02_Moninpeli.png mukaan."*
