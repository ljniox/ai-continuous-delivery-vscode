#!/usr/bin/env python3
"""
Script pour créer un enregistrement de run dans Supabase B
et définir les variables d'environnement GitHub Actions
"""

import os
import json
import uuid
from supabase import create_client, Client

def main():
    # Variables d'environnement
    supabase_url = os.getenv('SUPABASE_URL')
    supabase_key = os.getenv('SUPABASE_SERVICE_KEY')
    spec_id = os.getenv('SPEC_ID')
    github_run_id = os.getenv('GITHUB_RUN_ID', str(uuid.uuid4()))
    
    if not supabase_url or not supabase_key:
        print("❌ Variables SUPABASE_URL ou SUPABASE_SERVICE_KEY manquantes")
        exit(1)
    
    # Connexion Supabase
    supabase: Client = create_client(supabase_url, supabase_key)
    
    try:
        # Si pas de spec_id, on utilise la première spec disponible (pour les tests)
        if not spec_id:
            specs = supabase.table('specs').select('*').order('created_at', desc=True).limit(1).execute()
            if specs.data:
                spec_id = specs.data[0]['id']
                print(f"📋 Utilisation de la spec: {spec_id}")
        
        if not spec_id:
            print("❌ Aucune spec trouvée")
            exit(1)
        
        # Créer ou récupérer le sprint associé
        sprints = supabase.table('sprints').select('*').eq('spec_id', spec_id).execute()
        
        if not sprints.data:
            # Créer un sprint par défaut
            sprint_data = {
                'spec_id': spec_id,
                'label': 'S1',
                'dod_json': {
                    'coverage_min': 0.80,
                    'e2e_pass': True,
                    'lighthouse_min': 85
                }
            }
            sprint = supabase.table('sprints').insert(sprint_data).execute()
            sprint_id = sprint.data[0]['id']
            print(f"📊 Sprint créé: {sprint_id}")
        else:
            sprint_id = sprints.data[0]['id']
            print(f"📊 Sprint existant: {sprint_id}")
        
        # Créer l'enregistrement de run
        run_data = {
            'sprint_id': sprint_id,
            'ci_run_id': github_run_id,
            'started_at': 'now()',
            'result': None,
            'summary_json': {'status': 'STARTED'}
        }
        
        run = supabase.table('runs').insert(run_data).execute()
        run_id = run.data[0]['id']
        
        # Enregistrer un événement de statut
        supabase.table('status_events').insert({
            'run_id': run_id,
            'phase': 'PLANNING',
            'message': f'Démarrage du run {github_run_id}'
        }).execute()
        
        print(f"✅ Run créé: {run_id}")
        
        # Définir les variables de sortie pour GitHub Actions
        github_output = os.getenv('GITHUB_OUTPUT')
        if github_output:
            with open(github_output, 'a') as f:
                f.write(f"run_id={run_id}\n")
                f.write(f"sprint_id={sprint_id}\n")
                f.write(f"spec_id={spec_id}\n")
        
        # Créer aussi un fichier local pour les autres scripts
        os.makedirs('artifacts', exist_ok=True)
        with open('artifacts/run_context.json', 'w') as f:
            json.dump({
                'run_id': run_id,
                'sprint_id': sprint_id,
                'spec_id': spec_id,
                'ci_run_id': github_run_id
            }, f, indent=2)
        
        print(f"📝 Contexte sauvé dans artifacts/run_context.json")
        
    except Exception as e:
        print(f"❌ Erreur lors de la création du run: {e}")
        exit(1)

if __name__ == '__main__':
    main()