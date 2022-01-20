
import { ActivatedRoute, Router } from '@angular/router';
import { Component, OnInit, OnDestroy, ViewChild } from '@angular/core';
import { MatSidenav } from '@angular/material/sidenav';

import { Subscription } from 'rxjs';
import { TranslateService } from '@ngx-translate/core';

import { AuthService, User } from '../../components/auth/auth.service';
import { AppConfig } from '../../../conf/app.config';
import { GlobalSubService } from '../../services/global-sub.service';
import { SideNavService } from '../sidenav-items/sidenav-service';


@Component({
  selector: 'pnx-nav-home',
  templateUrl: './nav-home.component.html',
  styleUrls: ['./nav-home.component.scss']
})
export class NavHomeComponent implements OnInit, OnDestroy {

  public moduleName = 'Accueil';
  private subscription: Subscription;
  public currentUser: User;
  public appConfig: any;
  public currentDocUrl: string = 'https://preprod.biodiversite-bretagne.fr/accueil/presentation#top-tuto' ;
  public locale: string;
  @ViewChild('sidenav') public sidenav: MatSidenav;

  constructor(
    private translateService: TranslateService,
    public authService: AuthService,
    private activatedRoute: ActivatedRoute,
    public sideNavService: SideNavService,
    private globalSubService: GlobalSubService,
    private router: Router,
  ) {}

  ngOnInit() {
    // Inject App config to use in the template
    this.appConfig = AppConfig;

    // Subscribe to router event
    this.extractLocaleFromUrl();

    // Set the current module name in the navbar
    this.onModuleChange();

    // Init the sidenav instance in sidebar service
    this.sideNavService.setSideNav(this.sidenav);

    // Put the user name in navbar
    this.currentUser = this.authService.getCurrentUser();
  }


  private extractLocaleFromUrl() {
    this.subscription = this.activatedRoute.queryParams.subscribe((param: any) => {
      const locale = param['locale'];
      if (locale !== undefined) {
        this.defineLanguage(locale);
      } else {
        this.locale = this.translateService.getDefaultLang();
      }
    });
  }

  changeLanguage(lang) {
    this.defineLanguage(lang);
    const prev = this.router.url;
    this.router.navigate(['/']).then(data => {
      this.router.navigate([prev]);
    });
  }

  private defineLanguage(lang) {
    this.locale = lang;
    this.translateService.use(lang);
    this.translateService.setDefaultLang(lang);
  }

  private onModuleChange() {
    this.globalSubService.currentModuleSub.subscribe(module => {
      if (module) {
        this.moduleName = module.module_label;
        if (module.module_doc_url) {
          /*OEB*/
          /*this.currentDocUrl = module.module_doc_url;*/
	        this.currentDocUrl = "https://data.biodiversite-bretagne.fr/accueil/presentation#top-tuto";
        }
      } else {
        this.moduleName = 'Accueil';
      }
    });
  }

  closeSideBar() {
    this.sideNavService.sidenav.toggle();
  }

  ngOnDestroy() {
    // Prevent memory leak by unsubscribing
    this.subscription.unsubscribe();
  }
}
