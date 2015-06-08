# odoo_istall
Bash script for a complete odoo/ocb v8 install under ubuntu 14.04
.. image:: https://img.shields.io/badge/licence-AGPL--3-blue.svg
    :alt: License

Ubuntu installer
===================

This bash script install Odoo or Ocb (choice us menu driven).

The script install the postgresql server, (configuring user and connection/authentication settings files)
the neede python libraries
wkhtmltox 12.01 libraries
the odoo/ocb 8.0 branch, and its configuration file
italian localization module, creating symbolic links of directories in the addons dir
the init script for upstart daemon


Installation
============

root prermission required to run the script

Configuration
=============

Nothing special is needed to install this module.


Known issues / Roadmap
======================
Acqually only ubuntu 14.04 LTS suppoerted (32 and 64 bit)
ther are PROBLEMS with italian installation; after italian addons modules installation the server cannot start.
Removing the symlinks to italian addons everithing works flawlessy



Credits
=======

Contributors
------------

* Giuliano Lotta <giulano.lotta@gmail.com>

