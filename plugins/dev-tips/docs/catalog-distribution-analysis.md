# Distribúcia katalógu — analýza

Prečo dizajn v [catalog-distribution.md](catalog-distribution.md) vyzerá tak, ako vyzerá: ako to má
fungovať, v akom poradí to má prichádzať a ktoré alternatívy boli zamietnuté a na akom základe.

Design dokument hovorí *čo postaviť*. Tento hovorí *prečo* a je to dokument, ktorý si treba prečítať
znova skôr, než sa čokoľvek z toho prehodí.

## Ako to má fungovať

**Kód sa distribuuje s pluginom. Obsah nie.** Verzia pluginu sa mení vtedy, keď sa mení logika hookov,
čo je zriedka. Tipy sa k ľuďom dostanú bez toho, aby ktokoľvek niečo spúšťal.

Z pohľadu vývojára vyzerá jedna session takto. Pri štarte hook prečíta z lokálneho disku tri veci —
čo má nainštalované na stroji, čo nesie aktuálne repo v `.dev-tips/` a nacachovaný vzdialený katalóg —
zlúči ich a doručí najviac jeden tip. Na sieť sa nečaká. Počas session sa ďalej zaznamenáva ledger
príkazov a použitie skillov tak ako doteraz. Na konci turnu, ak je cache staršia než jej TTL, odpojený
proces ju obnoví pre nasledujúcu session a prebiehajúceho turnu sa to nijako nedotkne.

Z pohľadu autora to vyzerá takto. Niekto pridá skill alebo command do `Kros.AiDevTools` a v tom istom
pull requeste k nemu napíše `tip.json`; CI ho zvaliduje voči nástrojom, ktoré naozaj existujú, a PR sa
zmerguje. Niet čo publikovať — ten súbor **je** to, čo stroje čítajú. Do dňa je na každom stroji. Ak
sa tip ukáže ako nesprávny, opraví ho ďalší commit, alebo `enabled: false` umlčí všetko, kým sa to
nevyrieši.

Z ktorého z troch zdrojov tip pochádza, rozhoduje jedna otázka: **má už vývojár tú vec, o ktorej tip
hovorí?**

- Ak ju má, netreba publikovať vôbec nič. Skill je na jeho disku, jeho `description` hovorí, načo je,
  a `usage.json` hovorí, či ho niekedy spustil. Z toho vznikne *máš to a nikdy si to nepoužil*, čo je
  najsilnejšia forma tipu a nepotrebuje žiadny záznam v katalógu.
- Ak patrí repu, v ktorom práve pracuje, cestuje s tým repom a príde `git pull`-om.
- Objaviť sa nedá len nástroj, ktorý **nemá** — a len ten prípad potrebuje publikovaný katalóg.

## Prečo sa publikovanie musí zmeniť

Obsah tipov je zabalený v plugine, takže vydať jeden tip znamená bump verzie, update marketplacu,
update pluginu a reštart — a tri zo štyroch krokov patria vývojárovi, nie nám. Kto ich nikdy nespustí,
číta zastaraný katalóg donekonečna a ani jedna strana sa to nedozvie.

Tá istá väzba robí plugin neumlčateľným: tip, ktorý sa ukáže ako nesprávny, sa zobrazuje ďalej, kým sa
každý jeden človek individuálne neaktualizuje. Pri plugine, ktorého celou úlohou je oznamovať veci,
ktoré práve pribudli, je oboje naopak.

## V akom poradí to má prichádzať

| Etapa | Práca | Čo odomkne | Závisí od |
|---|---|---|---|
| 0 | Rozumné cooldowny v `catalog/config.json` | aby bol plugin vôbec znesiteľný | nič |
| 1 | Kanál A — lokálna detekcia | väčšina tipov prestane potrebovať záznam v katalógu | nič |
| 2 | Kanál B — `.dev-tips/` v produktových repách | ADR a konvencie per repo | nič |
| 3 | Kanál C — CI, fetch na pozadí | tipy na nástroje, ktoré vývojár nemá | prístup k CI v `Kros.AiDevTools` |
| 4 | Koniec ručného editovania `catalog/tips.json` | jediný zdroj pravdy | etapy 1–3 |

Poradie je podľa hodnoty na jednotku rizika. Kanál A nepotrebuje CI, sieť ani druhé repo a pokrýva
najväčšiu časť toho, čo by sa inak muselo písať ručne. Kanál C je posledný, lebo je jediný, ktorý
vyžaduje zmenu v repe, ktoré tento plugin nevlastní.

Meranie — či to vôbec mení správanie — zostáva mimo rozsahu. Zo stroja nič neodchádza.

## Register rozhodnutí

Každý záznam: čo bolo zvolené, voči čomu, a čo by oprávnilo prehodnotiť to.

### D1 — Obsah tipu žije vedľa nástroja, ktorý opisuje

**Zvolené:** `tip.json` vedľa skillu alebo commandu, vo vlastnom repe toho nástroja.

**Voči:**
- *Centrálnemu ručne udržiavanému katalógu.* Ten, kto premenuje command, nie je ten, kto si spomenie
  na tip, takže katalóg sa rozchádza a nikto si to nevšimne — jediní ľudia, ktorí tip čítajú, sú tí,
  čo ten nástroj nepoznajú, a tí nemajú ako rozpoznať, že je nesprávny.
- *`CLAUDE.md` alebo memory.* Oboje platí v každom turne, trvalo stojí kontext, nedá sa rate-limitovať,
  nedá sa zobraziť presne N-krát a nedá sa potlačiť pre niekoho, kto ten nástroj už používa. Tip je
  dočasné oznámenie, nie trvalá inštrukcia.

**Prehodnotiť, ak:** katalóg prestane rásť a nástroje sa prestanú premenúvať — vtedy je centrálna
kurácia menej mašinérie za ten istý výsledok.

### D2 — Tri kanály namiesto jedného

**Zvolené:** delenie podľa toho, či vývojár tú vec už má.

**Voči:** *jednému vzdialenému katalógu na všetko.* Jednoduchšie sa vysvetľuje, ale vyžaduje záznam
pre každý nástroj skôr, než sa o ňom dá čokoľvek povedať, a nevie vyjadriť najsilnejší dostupný tip —
že tento človek nástroj má a nikdy ho nespustil. Delenie zároveň znamená, že väčšina tipov nepotrebuje
publikačnú cestu vôbec.

**Prijatá cena:** tri vetvy kódu a krok zlúčenia namiesto jedného čítania.

### D3 — Detekcia používa `description` zo `SKILL.md`

**Zvolené:** keď `tip.json` neexistuje, text tipu sa vygeneruje z frontmatteru.

**Voči:** *vyžadovaniu `tip.json` pre všetko.* Lepší text, ale nový skill potom nemá tip, kým ho niekto
nenapíše — a to je presne to oneskorenie, kvôli ktorému tento dizajn vznikol.

**Známa slabina:** `description` je písaný preto, aby modelu povedal, kedy skill použiť, nie aby
presvedčil človeka vyskúšať ho. Niektoré budú čítať zle. Poistkou je, že `tip.json` ho prebíja, takže
zlý text sa dá opraviť bez zmeny mechanizmu.

**Prehodnotiť, ak:** sa v praxi ukáže, že väčšina vygenerovaných textov aj tak potrebuje prepísať.

### D4 — Vzdialený prenos je `git`

**Zvolené:** shallow fetch z bare repozitára v dátovom priečinku pluginu.

**Voči:**
- *Surovému HTTP s tokenom.* `Kros.AiDevTools` je privátne, takže by to znamenalo distribuovať
  credential vnútri pluginu nainštalovaného na stroji každého vývojára. Zamietnuté bez diskusie.
- *UNC file share.* Najjednoduchšie na firemnej LAN a bez credentials, ale zlyhá z domu aj cez VPN a
  nenesie históriu. Držané ako záloha, ak by `git` robil problémy.
- *Internej HTTP službe.* Hosting, nasadenie a monitoring kvôli jednému JSON súboru.

**Prečo to funguje:** `git` použije Git Credential Manager, ktorý vývojár musí mať nakonfigurovaný —
inak by mu nefungoval ani `plugin marketplace add`. Autentifikácia nestojí nič.

### D5 — Nepublikuje sa nič; klient číta zdroj

**Zvolené:** žiadny generovaný katalóg. Refresh fetchne `master` shallow a prečíta si autorské
`tip.json` priamo zo stromu; zvyšok si dopočíta sám.

**Voči:**
- *Orphan vetve s generovaným `tips.json`.* Funguje to, ale je to build artifact, ktorý treba držať v
  súlade so zdrojom, vyrába ho bot a nesie obsah, ktorý klient vie prečítať z toho zdroja rovnako
  lacno. Každý problém, ktorý priniesla — smyčka pri retriggeri, branch protection, artifact, ktorý
  môže zostarnúť — je problémom toho, že artifact vôbec existuje.
- *Generovanému súboru commitnutému do `master`.* Buď ho pushuje bot, s tými istými problémami so
  smyčkou a ochranou vetvy, alebo ho každý prispievateľ pregenerúva ručne — trenie umiestnené presne
  na ľudí, ktorí tipy píšu dobrovoľne.
- *GitHub release assetu.* Potrebuje API token proti privátnemu repu, čo je znova zamietnutá možnosť
  z D4.
- *Samostatnému repu.* Ďalšie repo na založenie, oprávnenia a udržiavanie v súlade, kvôli jednému
  súboru.

**Prijatá cena:** odvodzovanie `id`, `ref` a `install` sa presúva do klienta, takže zmena týchto
pravidiel si vyžiada vydanie pluginu. Menia sa ale rádovo zriedkavejšie než obsah, a to bolo celé
kritérium.

**Prehodnotiť, ak:** odvodzovanie prerastie to, čo je rozumné robiť v hooku, alebo repo narastie
natoľko, že shallow fetch jeho stromu prestane byť lacný.

### D6 — Refresh beží zo `Stop`, odpojene, na TTL

**Zvolené:** `Stop` skontroluje vek cache a keď je stará, spustí odpojený proces a skončí.

**Voči:**
- *Fetchu v `SessionStart`.* Dáva sieť na cestu k prvému promptu. Odmietnuté: sekunda pri štarte
  odinštaluje plugin rýchlejšie než akýkoľvek zlý tip.
- *`SessionStart` odpojene.* Pokrylo by aj session, v ktorých sa nedokončí žiadny turn, za cenu
  spustenia procesu pri každom štarte. Rozdiel je zanedbateľný; `Stop` vyhráva preto, že tam už
  bežia iné evidenčné veci.
- *Naplánovanej úlohe v OS.* Najspoľahlivejšia možnosť a zároveň najinvazívnejšia: plugin, ktorý
  zakladá Windows scheduled task, sa ťažko odinštaluje a ťažko obhajuje.

### D7 — Tipy sa doručujú len pri štarte session

**Zvolené:** prijať, že čerstvo stiahnutý katalóg použije až *nasledujúca* session.

**Voči:** *doručeniu uprostred session cez `UserPromptSubmit`*, na ktoré mašinéria existuje v
`Show-Candidate.ps1`. Zamietnuté preto, že plánovaný tip prerušujúci prácu je rušivejší než tip pri
štarte — retrospektívne oznámenie si to prerušenie zaslúži tým, že reaguje na to, čo vývojár práve
urobil, plánovaný tip nie. A nič sa tým nezíska: obsah s 24-hodinovým TTL nemá dôvod doraziť o
deväťdesiat sekúnd skôr.

### D8 — Politika cestuje v stiahnutom súbore a verí sa jej

**Zvolené:** `ttlHours`, `cooldownDays` a `enabled` žijú v katalógu; hodnoty v plugine slúžia len ako
bootstrap pre prvý fetch. Čo povie ten súbor, to hook urobí.

**Voči:**
- *Politike v plugine.* Každá zmena kadencie by si vyžiadala vydanie a — rozhodujúci bod — neexistoval
  by spôsob, ako umlčať zlý tip u všetkých bez toho, aby sa každý jeden človek aktualizoval.
- *Orezávaniu stiahnutých hodnôt na medze v hooku.* Zamietnuté. Medza je hádanie, ktorá hodnota je
  zlá, urobené skôr, než ktokoľvek videl plugin zlyhávať v prevádzke. Odpoveďou na zlý push je
  opravený push, alebo `enabled: false`, kým sa neopraví — oboje dorazí do jedného TTL, čo je
  rýchlejšie, než vydať nového klienta s inými medzami. Ak reálna prevádzka ukáže, že kadencia
  potrebuje spodnú hranicu, vtedy je čas zistiť, aká tá hranica je.

**Prijatý dôsledok:** zlý push rozkonfiguruje všetky stroje naraz, až kým to ďalší neopraví.

### D9 — `published` sa ruší v prospech lokálneho `firstSeen`

**Zvolené:** hook si do `shown.json` zapíše, kedy dané `id` videl prvý raz. Pole `published` neexistuje.

**Voči:**
- *Odvodeniu z git histórie.* Shallow fetch žiadnu nenesie a držať históriu kvôli datovaniu jedného
  poľa je veľká cena za malú vec.
- *Ručne písanému dátumu.* Rozchádza sa, zabúda sa naň a nikto ho v review nekontroluje.

**Prečo je lokálne lepšie, nielen lacnejšie:** to pole má povedať, aká nová je daná vec, a novosť je
relatívna voči čitateľovi. Pre niekoho, kto nastúpil minulý týždeň, je dva roky starý skill, o ktorom
nikdy nepočul, nový. `expires` zostáva autorským poľom — to, že obsah zastaral, je vlastnosťou obsahu,
nie čitateľa.

### D10 — Repo-lokálne tipy nikdy nevstupujú do centrálneho katalógu

**Zvolené:** `.dev-tips/` sa číta naživo z pracovného priečinka.

**Voči:** *ich zbieraniu do katalógu cez CI.* To potrebuje cross-repo token a druhú publikačnú cestu
pre obsah, ktorý už leží na disku, dá sa prečítať zadarmo a je správny pre každý worktree zvlášť.

### D11 — Použitie sa číta z transcriptov, nielen zaznamenáva dopredu

**Zvolené:** refresh na pozadí prejde `~/.claude/projects/**/*.jsonl`, nájde volania skillov a doplní
nimi `usage.json`, takže nástroj, ktorý niekto už používa, sa mu nikdy neponúkne.

**Voči:**
- *Zaznamenávaniu len od inštalácie ďalej*, čo sa deje dnes. Robí to z čerstvej inštalácie maximálne
  otravný zážitok: vývojárovi sa ponúkajú commandy, ktoré používa mesiace. To je jediná skúsenosť,
  po ktorej si plugin najpravdepodobnejšie vypne, a každého zasiahne presne raz — hneď v prvý deň.
- *Opýtaniu sa vývojára, čo už pozná.* Dotazník pri prvom spustení je trenie na najhoršom možnom
  mieste a ľudia aj tak podhodnocujú.

**Prijaté limity:** transcripty sa uchovávajú len obmedzený čas, takže *nikdy nepoužil* v skutočnosti
znamená *nepoužil v poslednom čase* — čo je na tento účel lepšia otázka. Skill zavolaný subagentom sa
počíta ako použitie. Platí to per stroj, ako každý iný signál tu.

### D12 — Detekcia ponúka len pluginy z našich marketplaceov

**Zvolené:** allow-list marketplaceov, defaultne `kros-ai-dev-tools` a `kros-plugins`, prepisateľný
cez `discoverMarketplaces` v stiahnutej konfigurácii.

**Voči:**
- *Ponúkaniu všetkého, čo je na stroji nainštalované.* Pôvodné správanie. Stroj bežne nesie aj
  cudzie nástroje — `superpowers`, `anthropic-skills` — ku ktorým sme nepísali text, nemáme pod
  kontrolou, kedy sa zmenia, a tip na ne minú to jedno oznámenie za cooldown na niečo, čo nám
  neprináleží odporúčať.
- *Filtrovaniu podľa prefixu názvu pluginu (`kros-*`).* Vyzerá jednoduchšie a je nesprávne: `teapie`
  ani `push` sa tak nevolajú, hoci naše sú. Vlastníctvo vyjadruje marketplace, nie názov.

**Prijatý dôsledok:** ak sa nájde cudzí nástroj, ktorý stále za propagáciu, treba ho do zoznamu
pridat vedome — alebo mu napísať vlastný `tip.json` a nespoliehať sa na jeho `description`.

## Riziká

| Riziko | Závažnosť | Odpoveď |
|---|---|---|
| Zlý push do `dev-tips/config.json` rozkonfiguruje všetkých | vysoká | opravený push, alebo `enabled: false`, do jedného TTL — zámerne bez poistky na strane klienta (D8) |
| Nikto nenapíše `tip.json`, takže cesta nič neprinesie | stredná | kanál A vyrába tipy bez akéhokoľvek písania |
| Vygenerovaný text číta zle | stredná | `tip.json` ho prebíja, tip po tipe |
| Retrospektívne oznámenia vyskočia na falošnú zhodu | stredná | formulácia zostáva *nabudúce môžeš*, nikdy *mal si* |
| Na desktope ide tip cez model, ktorý ho môže preformulovať | nízka | zdokumentované v `desktop-systemmessage-not-rendered.md`, issue nahlásené |
| Odpojený fetch zamrzne na výzve na credentials | nízka | promptovanie vypnuté, tvrdý timeout, lock so stale timeoutom |

## Otvorené otázky

1. **Kto vie pridať validačný workflow do `Kros.AiDevTools`?** Etapa 3 už nepotrebuje vetvu ani bota,
   ale stále potrebuje niekoho, kto tam vie pridať CI. Vlastníctvo nie je určené.
2. **Kde je `655507-dev-tips-plugin.md`?** README ho uvádza ako dizajn, o ktorý sa opiera; na tomto
   stroji nie je v žiadnom repe. Buď ho prelinkovať, alebo tú zmienku zrušiť.
3. **Stačí vypnutie promptovania GCM v praxi?** Spôsob zlyhania — skrytý proces visiaci navždy — je
   dosť závažný na to, aby si zaslúžil zámerný test s vymazaným credentialom, nie predpoklad.
4. **Ako by sme vôbec zistili, že to funguje?** Meranie neexistuje a neplánuje sa. Prijaté, ale
   znamená to, že každé rozhodnutie tu stojí na úvahe, nie na dôkaze, a jediný spôsob, ako ich
   opraviť, je dať tú vec pred ľudí a sledovať, čo si vypnú.
