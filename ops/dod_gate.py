#!/usr/bin/env python3
"""
Script DoD Gate - Valide les critères de Definition of Done
et décide si le sprint peut être mergé
"""

import os
import json
from pathlib import Path
from supabase import create_client, Client

def evaluate_dod(summary, dod_criteria):
    """
    Évalue si les critères DoD sont respectés
    """
    results = {
        'passed': True,
        'details': [],
        'score': 0,
        'total_criteria': 0
    }
    
    # Coverage minimum
    if 'coverage_min' in dod_criteria:
        coverage_min = dod_criteria['coverage_min']
        actual_coverage = summary.get('coverage', 0)
        
        if actual_coverage >= coverage_min:
            results['details'].append(f"✅ Coverage: {actual_coverage:.1%} >= {coverage_min:.1%}")
            results['score'] += 1
        else:
            results['details'].append(f"❌ Coverage: {actual_coverage:.1%} < {coverage_min:.1%}")
            results['passed'] = False
        results['total_criteria'] += 1
    
    # Tests E2E passent
    if dod_criteria.get('e2e_pass', False):
        e2e_pass = summary.get('e2e_pass', False)
        if e2e_pass:
            results['details'].append("✅ Tests E2E: Passés")
            results['score'] += 1
        else:
            results['details'].append("❌ Tests E2E: Échecs")
            results['passed'] = False
        results['total_criteria'] += 1
    
    # Tests unitaires passent
    unit_pass = summary.get('unit_pass', False)
    if unit_pass:
        results['details'].append("✅ Tests unitaires: Passés")
        results['score'] += 1
    else:
        results['details'].append("❌ Tests unitaires: Échecs")
        results['passed'] = False
    results['total_criteria'] += 1
    
    # Score Lighthouse minimum
    if 'lighthouse_min' in dod_criteria:
        lighthouse_min = dod_criteria['lighthouse_min']
        actual_lighthouse = summary.get('lighthouse', 0)
        
        if actual_lighthouse >= lighthouse_min:
            results['details'].append(f"✅ Lighthouse: {actual_lighthouse} >= {lighthouse_min}")
            results['score'] += 1
        else:
            results['details'].append(f"❌ Lighthouse: {actual_lighthouse} < {lighthouse_min}")
            results['passed'] = False
        results['total_criteria'] += 1
    
    return results

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
    
    # Charger le résumé des tests
    summary_file = Path('artifacts/summary.json')
    if not summary_file.exists():
        print("❌ Fichier artifacts/summary.json non trouvé")
        exit(1)
    
    with open(summary_file, 'r') as f:
        summary = json.load(f)
    
    print(f"🔍 Évaluation DoD pour le run {run_id}")
    
    try:
        # Récupérer les informations du run et du sprint
        run_data = supabase.table('runs').select('*, sprints(*)').eq('id', run_id).single().execute()
        
        if not run_data.data:
            print("❌ Run non trouvé")
            exit(1)
        
        run = run_data.data
        sprint = run['sprints']
        dod_criteria = sprint['dod_json']
        
        print(f"📋 Sprint: {sprint['label']}")
        print(f"📊 Critères DoD: {json.dumps(dod_criteria, indent=2)}")
        
        # Évaluer les critères
        evaluation = evaluate_dod(summary, dod_criteria)
        
        print(f"\n🎯 Résultat DoD: {evaluation['score']}/{evaluation['total_criteria']}")
        for detail in evaluation['details']:
            print(f"   {detail}")
        
        # Mettre à jour le résumé
        summary['dod_evaluation'] = evaluation
        summary['result'] = 'PASSED' if evaluation['passed'] else 'FAILED'
        
        # Sauvegarder le résumé mis à jour
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)
        
        # Mettre à jour le run dans la base
        run_update = {
            'finished_at': 'now()',
            'result': summary['result'],
            'summary_json': summary
        }
        
        supabase.table('runs').update(run_update).eq('id', run_id).execute()
        
        # Mettre à jour le statut du sprint
        sprint_state = 'DONE' if evaluation['passed'] else 'FAILED'
        supabase.table('sprints').update({'state': sprint_state}).eq('id', sprint['id']).execute()
        
        # Enregistrer un événement de statut final
        final_phase = 'TESTS_PASSED' if evaluation['passed'] else 'TESTS_FAILED'
        supabase.table('status_events').insert({
            'run_id': run_id,
            'phase': final_phase,
            'message': f"DoD {summary['result']}: {evaluation['score']}/{evaluation['total_criteria']} critères"
        }).execute()
        
        if evaluation['passed']:
            print("\n✅ DoD PASSÉ - Sprint prêt pour merge")
            exit(0)
        else:
            print("\n❌ DoD ÉCHOUÉ - Corrections nécessaires")
            exit(1)
            
    except Exception as e:
        print(f"❌ Erreur lors de l'évaluation DoD: {e}")
        
        # Marquer comme échec en cas d'erreur
        summary['result'] = 'FAILED'
        summary['error'] = str(e)
        
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)
        
        supabase.table('runs').update({
            'finished_at': 'now()',
            'result': 'FAILED',
            'summary_json': summary
        }).eq('id', run_id).execute()
        
        exit(1)

if __name__ == '__main__':
    main()