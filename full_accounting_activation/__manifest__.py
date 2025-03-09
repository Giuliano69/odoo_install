# Copyright 2019-2021 Sergio Zanchetta (Associazione PNLUG - Gruppo Odoo)
# License AGPL-3.0 or later (http://www.gnu.org/licenses/agpl).

{
    'name': 'Full Accounting Activation',
    'summary': 'Base module to enable full accounting feature for admin user',
    'version': '18.0.1.0.0',
    'category': 'Hidden',
    'author': "Sergio Zanchetta",
    'website': 'https://gitlab.com/PNLUG/Odoo/repository/iso_addons',
    'license': 'AGPL-3',
    "depends": [
        'account',
    ],
    "data": [
        'data/account_default.xml',
    ],
    'installable': True,
}
