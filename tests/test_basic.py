"""Tests basiques pour vérifier l'environnement"""

def test_basic():
    """Test qui doit toujours passer"""
    assert True

def test_imports():
    """Test des imports essentiels"""
    import json
    import os
    import sys
    assert json and os and sys
    
def test_python_version():
    """Test de la version Python"""
    import sys
    assert sys.version_info >= (3, 8)