#!/usr/bin/env python3
"""
Script pour uploader les artefacts (rapports de tests) vers Supabase B Storage
et enregistrer les métadonnées en base
"""

import os
import json
import glob
from pathlib import Path
from supabase import create_client, Client

def get_file_size(filepath):
    """Récupère la taille d'un fichier en bytes"""
    try:
        return os.path.getsize(filepath)
    except:
        return 0

def upload_file_to_storage(supabase: Client, filepath: str, storage_path: str):
    """Upload un fichier vers Supabase Storage"""
    try:
        with open(filepath, 'rb') as f:
            result = supabase.storage.from_('automation').upload(
                storage_path, f, file_options={'content-type': 'application/octet-stream'}
            )
        return True
    except Exception as e:
        print(f"❌ Erreur upload {filepath}: {e}")
        return False

def main():
    # Variables d'environnement
    supabase_url = os.getenv('SUPABASE_URL')
    supabase_key = os.getenv('SUPABASE_SERVICE_KEY')
    run_id = os.getenv('RUN_ID')
    
    if not supabase_url or not supabase_key or not run_id:
        print("❌ Variables SUPABASE_URL, SUPABASE_SERVICE_KEY ou RUN_ID manquantes")
        exit(1)
    
    # Connexion Supabase
    supabase: Client = create_client(supabase_url, supabase_key)
    
    # Répertoire des artefacts
    artifacts_dir = Path('artifacts')
    if not artifacts_dir.exists():
        print("⚠️  Répertoire artifacts/ non trouvé")
        return
    
    # Mapping des types d'artefacts
    artifact_patterns = {
        'junit': ['**/junit*.xml', '**/test-results.xml', '**/pytest.xml'],
        'coverage': ['**/coverage*.xml', '**/coverage*.json', '**/htmlcov/**'],
        'lighthouse': ['**/lighthouse*.json', '**/lh-*.json'],
        'logs': ['**/logs/**', '**/*.log']
    }
    
    uploaded_artifacts = []
    
    print(f"📦 Upload des artefacts pour le run {run_id}...")
    
    for artifact_kind, patterns in artifact_patterns.items():
        for pattern in patterns:
            files = glob.glob(str(artifacts_dir / pattern), recursive=True)
            
            for filepath in files:
                if os.path.isfile(filepath):
                    # Chemin relatif depuis artifacts/
                    rel_path = os.path.relpath(filepath, artifacts_dir)
                    storage_path = f"reports/{run_id}/{artifact_kind}/{rel_path}"
                    
                    print(f"  📤 {rel_path} -> {storage_path}")
                    
                    # Upload vers Supabase Storage
                    if upload_file_to_storage(supabase, filepath, storage_path):
                        # Enregistrer en base
                        artifact_data = {
                            'run_id': run_id,
                            'kind': artifact_kind,
                            'storage_path': storage_path,
                            'size': get_file_size(filepath)
                        }
                        
                        result = supabase.table('artifacts').insert(artifact_data).execute()
                        if result.data:
                            artifact_id = result.data[0]['id']
                            uploaded_artifacts.append({
                                'id': artifact_id,
                                'kind': artifact_kind,
                                'storage_path': storage_path,
                                'size': get_file_size(filepath)
                            })
                            print(f"    ✅ Enregistré: {artifact_id}")
    
    # Mettre à jour le résumé
    summary_file = artifacts_dir / 'summary.json'
    if summary_file.exists():
        with open(summary_file, 'r') as f:
            summary = json.load(f)
    else:
        summary = {}
    
    summary['uploaded_artifacts'] = len(uploaded_artifacts)
    summary['artifacts_detail'] = uploaded_artifacts
    
    # Sauvegarder le résumé mis à jour
    with open(summary_file, 'w') as f:
        json.dump(summary, f, indent=2)
    
    print(f"✅ {len(uploaded_artifacts)} artefacts uploadés")
    
    # Enregistrer un événement de statut
    supabase.table('status_events').insert({
        'run_id': run_id,
        'phase': 'ARTIFACTS_UPLOADED',
        'message': f'{len(uploaded_artifacts)} artefacts uploadés'
    }).execute()

if __name__ == '__main__':
    main()