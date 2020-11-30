#jPlatformDeploy

<p>
  <a href="https://travis-ci.com/github/departement-loire-atlantique/jPlatformDeploy">
    <img src="https://travis-ci.com/departement-loire-atlantique/jPlatformDeploy.svg?branch=master" />
  </a>
</p>

# JCMS 10 - Différents outils pour livrer un site jcms

Ce projet a pour but de fournir un enemble d'outils pour builder les livrables ainsi que leurs deploiements sur les différents sites.

## Objectifs

1. Construire le WAR global pour une première installation de site web
2. Livrer ou mettre à jour un module en particulier
3. Mettre à jour tout le site en relivrant le war global

## Mode opératoire

Les livrables sont générés et archivés dans github. Le build des livrables est effectué par travis qui se base sur une image docker contenant l'outil ant que nous utilisons pour construire les livrables. La commande utilisée est `ant makeWarSocle`.

**Un build est lancé à chaque tag du repo.**
