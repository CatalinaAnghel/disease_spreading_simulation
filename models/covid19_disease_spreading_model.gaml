/**
* Name: covid19_spreading_model
* Author: Florina-Catalina Anghel
* Description: Simulate the COVID-19 transmission in Craiova, Romania.
* Based on the Luneray's Flu tutorial which is provided by GAMA Platform
* Tags: covid-19, transmission, vaccine, masks, mortality rates, comorbidities
*/
model covid19_spreading_model

global {
// experiment settings
	int nb_people <- 900;
	int nb_infected_init <- 50;
	float max_health <- 1.0;
	float step <- 15 #mn;
	int minimum_exposure <- 1;
	int nb_days <- 0;
	float travel_probability <- 0.05;

	// environmental settings:
	file roads_shapefile <- file("../includes/roads_valea_rosie.shp");
	file buildings_shapefile <- file("../includes/buildings_valea_rosie.shp");
	geometry shape <- envelope(roads_shapefile);
	bool clean_data <- true;
	//tolerance for reconnecting nodes
	float tolerance <- 3.0;
	//if true, split the lines at their intersection
	bool split_lines <- true;
	//if true, keep only the main connected components of the network
	bool reduce_to_main_connected_components <- true;
	graph road_network;

	// transmission settings:
	float asymptomatic_rate <- 0.42;
	float mask_infection_rate <- 0.23; // 23% of the susceptible people that wear masks correctly will be infected
	int nb_minimum_days_carrier <- 2 #day;
	int nb_days_sympt_apparition <- 5 #day;
	int nb_maximum_days_carrier <- 14 #day;
	float transmission_distance <- 1.5 #m;

	// disease prevention settings:
	bool vaccine <- false;
	int vaccination_phase <- 1;
	float phase1_rate <- 0.83;
	int nb_people_eligible_phase1 <- int(phase1_rate * nb_people / 100);
	bool mandatory_masks <- false;
	float wear_masks_rate <- 0.43;
	int nb_people_with_masks <- int(wear_masks_rate * nb_people);
	float vaccine_efficacity <- 0.956;
	int nb_days_vaccine_recovered <- 90 #day;
	float vaccination_rate <- 0.383; // almost 38.3% persons will want to get vaccinated

	// mortality rates (gender, age, comorbidities):
	float male_mortality_rate <- 0.618; // 61.8% from the total deaths are male.
	// 17 years old and under
	list<float> age_17_mortality_rate <- [0.0004, 0.0039, 0.0732];
	// 18 - 29 with 0, 1, 2+ comorbidities
	list<float> age_29_mortality_rate <- [0.001, 0.0112, 0.0711];
	// 30 - 39 with 0, 1, 2+ comorbidities
	list<float> age_39_mortality_rate <- [0.0026, 0.0223, 0.0965];
	// 40 - 49 with 0, 1, 2+ comorbidities
	list<float> age_49_mortality_rate <- [0.0065, 0.0351, 0.118];
	// 50 - 59 with 0, 1, 2+ comorbidities
	list<float> age_59_mortality_rate <- [0.0147, 0.0578, 0.1647];
	// 60 - 69 with 0, 1, 2+ comorbidities
	list<float> age_69_mortality_rate <- [0.0407, 0.1271, 0.2626];
	// 70 - 79 with 0, 1, 2+ comorbidities
	list<float> age_79_mortality_rate <- [0.1114, 0.2776, 0.3919];
	// 80+ with 0, 1, 2+ comorbidities
	list<float> age_80_mortality_rate <- [0.2112, 0.4884, 0.5274];
	int nb_people_infected <- nb_infected_init update: people count (each.is_infected);
	int nb_people_not_infected <- nb_people - nb_infected_init update: people count (each.is_susceptible);
	int nb_people_vaccinated_first_dose <- 0 update: people count (each.nb_vaccines = 1);
	int nb_people_vaccinated_second_dose <- 0 update: people count (each.nb_vaccines = 2);
	int nb_people_fully_vaccinated <- 0 update: people count (each.nb_vaccines = 3);
	int nb_people_phase1 <- 0 update: people count (each.vaccination_phase_eligible = 1);
	int nb_people_phase2 <- 0 update: people count (each.vaccination_phase_eligible = 2);
	int nb_people_phase3 <- 0 update: people count (each.vaccination_phase_eligible = 3);
	int nb_quarantined_people <- 0 update: people count (each.is_quarantined);
	int nb_people_recovered <- 0 update: people count (each.is_recovered);
	int nb_females <- 0 update: people count (each.gender = 1);

	// population:
	int nb_people_under_17 <- 0 update: people count (each.age <= 17);
	int nb_people_under_29 <- 0 update: people count (each.age <= 29 and each.age > 17);
	int nb_people_under_39 <- 0 update: people count (each.age <= 39 and each.age > 29);
	int nb_people_under_49 <- 0 update: people count (each.age <= 49 and each.age > 39);
	int nb_people_under_59 <- 0 update: people count (each.age <= 59 and each.age > 49);
	int nb_people_under_69 <- 0 update: people count (each.age <= 69 and each.age > 59);
	int nb_people_under_79 <- 0 update: people count (each.age <= 79 and each.age > 69);
	int nb_people_over_80 <- 0 update: people count (each.age >= 80);
	float people_under_20_rate <- 0.331;
	float people_under_39_rate <- 0.299;
	float people_under_59_rate <- 0.231;
	float people_under_79_rate <- 0.119;
	float people_under_99_rate <- 0.019;

	// deaths:
	int nb_deaths <- 0;
	int nb_female_deaths <- 0;
	int nb_deaths_under_17 <- 0;
	int nb_deaths_under_29 <- 0;
	int nb_deaths_under_39 <- 0;
	int nb_deaths_under_49 <- 0;
	int nb_deaths_under_59 <- 0;
	int nb_deaths_under_69 <- 0;
	int nb_deaths_under_79 <- 0;
	int nb_deaths_over_80 <- 0;
	int nb_deaths_without_comorbidities <- 0;
	int nb_deaths_1_comorbidity <- 0;
	int nb_deaths_2_comorbidities <- 0;
	int nb_deaths_vaccinated_people <- 0;
	float female_max_health_update <- 0.03;
	float male_max_health_update <- 0.04;

	// rates:
	float infected_rate update: nb_people_infected / nb_people * 100;
	float vaccinated_rate update: (nb_people_vaccinated_first_dose + nb_people_vaccinated_second_dose + nb_people_fully_vaccinated) / nb_people * 100;

	init {
	//clean data, with the given options
		list<geometry> clean_lines <- clean_data ? clean_network(roads_shapefile.contents, tolerance, split_lines, reduce_to_main_connected_components) : roads_shapefile.contents;

		//create road from the clean lines
		create road from: clean_lines;
		road_network <- as_edge_graph(road);

		// create the buildings
		create building from: buildings_shapefile;

		// create the persons
		create people number: nb_people {
			location <- any_location_in(one_of(building));
			home_building <- one_of(building);
			home <- any_location_in(home_building);
		}

		// infect some people
		ask nb_infected_init among people {
			is_infected <- true;
			is_susceptible <- false;
		}

		// masks settings
		ask int(wear_masks_rate * nb_people) among people {
			wears_mask <- true;
		}

		// make the rest of the population susceptible
		list<people> remaining_people <- people where (!each.is_infected);
		ask remaining_people {
			is_susceptible <- true;
		}

		// generate the age groups:
		ask int(nb_people * people_under_20_rate) among people {
			age <- rnd(7) + 12;
		}

		list<people> remaining_people <- people where (each.age = 0);
		ask int(nb_people * people_under_39_rate) among remaining_people {
			age <- rnd(19) + 20;
		}

		list<people> remaining_people <- people where (each.age = 0);
		ask int(nb_people * people_under_59_rate) among remaining_people {
			age <- rnd(19) + 40;
		}

		list<people> remaining_people <- people where (each.age = 0);
		ask int(nb_people * people_under_79_rate) among remaining_people {
			age <- rnd(19) + 60;
		}

		list<people> remaining_people <- people where (each.age = 0);
		ask int(nb_people * people_under_99_rate) among remaining_people {
			age <- rnd(19) + 80;
		}

		list<people> remaining_people <- people where (each.age = 0);
		ask remaining_people {
			age <- rnd(20) + 100;
		}

		// define the vaccination phases
		ask nb_people_eligible_phase1 among people {
			vaccination_phase_eligible <- 1;
		}

		list<people> remaining_people <- people where (each.vaccination_phase_eligible = 0 and (each.nb_comorbidities = 2 or each.age >= 65));
		ask remaining_people {
			vaccination_phase_eligible <- 2;
		}

		list<people> remaining_people <- people where (each.vaccination_phase_eligible = 0);
		ask remaining_people {
			vaccination_phase_eligible <- 3;
		}

		ask (nb_people * vaccination_rate) among people {
			wants_vaccine <- true;
		}

	}

	reflex end_simulation when: infected_rate = 100 or nb_people = 0 or nb_people_infected = 0 {
		do pause;
	}

	reflex begin_new_day when: every(1 #day) {
		nb_days <- nb_days + 1;
	}

}

species people skills: [moving] {
// location settings
	point home <- nil;
	building home_building <- nil;

	// physical attributes:
	int gender;
	float speed;
	float health;
	int age;
	int nb_comorbidities;

	// disease-related attributes:
	bool is_infected;
	bool is_susceptible;
	bool is_recovered;
	bool is_quarantined;
	bool is_asymptomatic;
	bool will_develop_symptoms;
	bool quarantined_home;
	int infection_cycle;
	int recovery_cycle;
	float total_mortality_probability;

	// vaccine-related info
	int nb_vaccines;
	bool wears_mask;
	int vaccination_phase_eligible;
	int last_vaccine_dose_cycle;
	bool wants_vaccine;

	// daily values
	int current_day_exposure;
	point target;

	init {
		current_day_exposure <- 0;
		vaccination_phase_eligible <- 0;
		wants_vaccine <- false;
		last_vaccine_dose_cycle <- 0;
		total_mortality_probability <- 0;
		is_infected <- false;
		is_susceptible <- false;
		is_recovered <- false;
		is_quarantined <- false;
		is_asymptomatic <- true;
		will_develop_symptoms <- false;
		quarantined_home <- false;
		infection_cycle <- 0;
		recovery_cycle <- 0;
		gender <- rnd_choice([0::0.5, 1::0.5]);
		speed <- (2 + rnd(3)) #km / #h;
		health <- rnd(max_health);
		age <- 0;
		nb_comorbidities <- int(rnd(2));
	}

	reflex stay when: target = nil and !is_quarantined {
	// stay or move to one of the buildings
		if flip(travel_probability) {
			target <- any_location_in(one_of(building));
		}

	}

	reflex move when: target != nil and !is_quarantined {
	// go to another location
		do goto target: target on: road_network;
		if (location = target) {
			target <- nil;
		}

	}

	reflex stay_at_home when: is_quarantined {
		if !quarantined_home {
		// go home and stay there
			do goto target: home on: road_network;
			if location = home {
				target <- nil;
				quarantined_home <- true;
			}

		}

	}

	reflex get_quarantined when: !is_asymptomatic and is_infected and cycle >= infection_cycle + nb_minimum_days_carrier / step and (health <= 0.7 or flip(0.5)) {
	// the agent will be quarantined together with his/her family
		is_quarantined <- true;
		list<people> flatmates <- people where (each.home_building = self.home_building);
		ask flatmates {
			is_quarantined <- true;
		}

	}

	reflex infect when: is_infected and cycle >= infection_cycle + nb_minimum_days_carrier / step {
		ask people at_distance transmission_distance {
			current_day_exposure <- current_day_exposure + 1;
			if !is_infected and current_day_exposure >= minimum_exposure and (((wears_mask or self.wears_mask) and flip(mask_infection_rate)) or !wears_mask) and ((nb_vaccines > 0 and
			!flip(vaccine_efficacity) and cycle <= last_vaccine_dose_cycle + 6 #month / step) or is_susceptible) {
			// the person has been exposed for more than 15 minutes, so it is infected.
				is_infected <- true;
				is_susceptible <- false;
				is_recovered <- false;
				infection_cycle <- cycle;
			}

		}

	}

	reflex get_vaccinated when: ((nb_vaccines = 0 or (nb_vaccines = 1 and cycle >= last_vaccine_dose_cycle + 21 #day / step) or (nb_vaccines = 2 and
	cycle >= last_vaccine_dose_cycle + 6 #month / step)) and vaccination_phase >= vaccination_phase_eligible) and vaccine = true and wants_vaccine and age >= 16 and ((is_recovered
	and cycle >= recovery_cycle + nb_days_vaccine_recovered / step and recovery_cycle > 0) or is_susceptible) {
		nb_vaccines <- nb_vaccines + 1;
		last_vaccine_dose_cycle <- cycle;
		write 'Gets vaccinated with the dose no. ' + nb_vaccines;
		if nb_vaccines = 1 {
			nb_people_vaccinated_first_dose <- nb_people_vaccinated_first_dose + 1;
		} else if nb_vaccines = 2 {
			nb_people_vaccinated_second_dose <- nb_people_vaccinated_second_dose + 1;
			nb_people_vaccinated_first_dose <- nb_people_vaccinated_first_dose - 1;
		} else {
			nb_people_fully_vaccinated <- nb_people_fully_vaccinated + 1;
			nb_people_vaccinated_second_dose <- nb_people_vaccinated_second_dose - 1;
		}

	}

	reflex die when: health <= 0 {
		nb_people <- nb_people - 1;
		nb_deaths <- nb_deaths + 1;

		// count the age groups deaths
		switch age {
			match_between [0, 17] {
				nb_deaths_under_17 <- nb_deaths_under_17 + 1;
			}

			match_between [18, 29] {
				nb_deaths_under_29 <- nb_deaths_under_29 + 1;
			}

			match_between [30, 39] {
				nb_deaths_under_39 <- nb_deaths_under_39 + 1;
			}

			match_between [40, 49] {
				nb_deaths_under_49 <- nb_deaths_under_49 + 1;
			}

			match_between [50, 59] {
				nb_deaths_under_59 <- nb_deaths_under_59 + 1;
			}

			match_between [60, 69] {
				nb_deaths_under_69 <- nb_deaths_under_69 + 1;
			}

			match_between [70, 79] {
				nb_deaths_under_79 <- nb_deaths_under_79 + 1;
			}

			match_between [80, 100] {
				nb_deaths_over_80 <- nb_deaths_over_80 + 1;
			}

		}

		// count the deaths per gender
		if gender = 1 {
			nb_female_deaths <- nb_female_deaths + 1;
		}

		// count the deaths per number of comorbidities
		switch nb_comorbidities {
			match 0 {
				nb_deaths_without_comorbidities <- nb_deaths_without_comorbidities + 1;
			}

			match 1 {
				nb_deaths_1_comorbidity <- nb_deaths_1_comorbidity + 1;
			}

			match 2 {
				nb_deaths_2_comorbidities <- nb_deaths_2_comorbidities + 1;
			}

		}

		// count the deaths per vaccination status
		if nb_vaccines > 0 and cycle < (last_vaccine_dose_cycle + 6 #months / step) {
			nb_deaths_vaccinated_people <- nb_deaths_vaccinated_people + 1;
		}

		do die;
	}

	reflex become_symptomatic when: is_infected and cycle > infection_cycle + rnd(5) #day / step and (is_asymptomatic and flip(asymptomatic_rate)) {
	// the agent will become symptomatic
		will_develop_symptoms <- true;
	}

	reflex update_health when: is_infected and cycle > infection_cycle + rnd(5) #day / step and will_develop_symptoms {
		is_asymptomatic <- false;

		// get the mortality probability based on age and the number of comorbidities
		float age_probability <- 0.0;
		switch age {
			match_between [0, 17] {
				total_mortality_probability <- age_17_mortality_rate[nb_comorbidities];
			}

			match_between [18, 29] {
				total_mortality_probability <- age_29_mortality_rate[nb_comorbidities];
			}

			match_between [30, 39] {
				total_mortality_probability <- age_39_mortality_rate[nb_comorbidities];
			}

			match_between [40, 49] {
				total_mortality_probability <- age_49_mortality_rate[nb_comorbidities];
			}

			match_between [50, 59] {
				total_mortality_probability <- age_59_mortality_rate[nb_comorbidities];
			}

			match_between [60, 69] {
				total_mortality_probability <- age_69_mortality_rate[nb_comorbidities];
			}

			match_between [70, 79] {
				total_mortality_probability <- age_79_mortality_rate[nb_comorbidities];
			}

			match_between [80, 100] {
				total_mortality_probability <- age_80_mortality_rate[nb_comorbidities];
			}

		}

		if flip(total_mortality_probability) {
		// the agent will become sicker
			float gender_health_update_value <- (gender = 1) ? female_max_health_update : female_max_health_update;
			health <- health - rnd(gender_health_update_value);
		} else if cycle >= infection_cycle + (rnd(10) + 2) #day / step {
		// the agent will become healthier
			health <- health + rnd(0.2);
			if health > 1.0 {
				health <- 1.0;
			}

		}

	}

	reflex get_healthy when: is_infected and cycle = infection_cycle + nb_maximum_days_carrier / step {
	// the agent will recover from the disease
		is_asymptomatic <- true;
		is_infected <- false;
		is_recovered <- true;
		is_susceptible <- false;
		recovery_cycle <- cycle;

		// compute the current health status
		health <- health + rnd(1);
		if health > 1.0 {
			health <- 1.0;
		}

		// the quarantine is over
		is_quarantined <- false;
		quarantined_home <- false;
		will_develop_symptoms <- false;
		list<people> flatmates <- people where (each.home_building = self.home_building);
		ask flatmates {
			is_quarantined <- false;
			quarantined_home <- false;
		}

	}

	reflex become_susceptible when: !is_infected and ((is_recovered and cycle > recovery_cycle + 6 #month / step) or (nb_vaccines > 0 and cycle <= last_vaccine_dose_cycle + 6
	#month / step)) {
	// after 6 months, the person is susceptible
		is_susceptible <- true;
		is_recovered <- false;
	}

	reflex reset_exposure when: every(1 #day) {
		current_day_exposure <- 0;
	}

	reflex get_old when: every(1 #year) and cycle >= 1#year/step {
		age <- age + 1;
	}

	aspect circle {
	// color the agent based on his/her status
		rgb color <- #green;
		if is_infected {
			color <- #red;
		} else if (nb_vaccines > 0) {
			color <- #blue;
		} else if is_susceptible {
			color <- #green;
		} else if is_recovered {
			color <- #purple;
		}

		draw circle(5) color: color;
	} }

	// Road
species road {

	aspect geom {
		draw shape color: #black;
	}

}

// Building
species building {

	aspect geom {
		draw shape color: #gray;
	}

}

experiment covid19_spreading_experiment type: gui {
	parameter "Number of people infected at init" var: nb_infected_init min: 1 max: 900;
	parameter "The population can be vaccinated" var: vaccine min: 0 max: 1;
	parameter "Current vaccination phase" var: vaccination_phase among: [1, 2, 3];
	parameter "The masks are mandatory" var: mandatory_masks min: 0 max: 1;
	parameter "The probability to leave the current building:" var: travel_probability min: 0 max: 1;
	output {
		monitor "Remaining population" value: nb_people;
		monitor "Number of females" value: nb_females;
		monitor "Deaths" value: nb_deaths;
		monitor "Recovered" value: nb_people_recovered;
		monitor "Infected people rate (total)" value: infected_rate;
		monitor "Currently infected people" value: nb_people_infected;
		monitor "Vaccinated people rate" value: vaccinated_rate;
		monitor "Phase 1 eligible people" value: nb_people_phase1;
		monitor "Phase 2 eligible people" value: nb_people_phase2;
		monitor "Phase 3 eligible people" value: nb_people_phase3;
		monitor "The number of quarantined people" value: nb_quarantined_people;
		monitor "Current day of the simulation" value: nb_days;
		monitor "Population under 17 years old" value: nb_people_under_17;
		monitor "Population 18-29 years old" value: nb_people_under_29;
		monitor "Population 30-39 years old" value: nb_people_under_39;
		monitor "Population 40-49 years old" value: nb_people_under_49;
		monitor "Population 50-59 years old" value: nb_people_under_59;
		monitor "Population 60-69 years old" value: nb_people_under_69;
		monitor "Population 70-79 years old" value: nb_people_under_79;
		monitor "Population 80+" value: nb_people_over_80;
		monitor "Female deaths" value: nb_female_deaths;
		monitor "Deaths under 17 years old" value: nb_deaths_under_17;
		monitor "Deaths 18-29 years old" value: nb_deaths_under_29;
		monitor "Deaths 30-39 years old" value: nb_deaths_under_39;
		monitor "Deaths 40-49 years old" value: nb_deaths_under_49;
		monitor "Deaths 50-59 years old" value: nb_deaths_under_59;
		monitor "Deaths 60-69 years old" value: nb_deaths_under_69;
		monitor "Deaths 70-79 years old" value: nb_deaths_under_79;
		monitor "Deaths 80+" value: nb_deaths_over_80;
		monitor "Deaths (persons without comorbities)" value: nb_deaths_without_comorbidities;
		monitor "Deaths (1 comorbidity)" value: nb_deaths_1_comorbidity;
		monitor "Deaths (2 comorbidities)" value: nb_deaths_2_comorbidities;
		monitor "Deaths (vaccinated people)" value: nb_deaths_vaccinated_people;
		display map {
			species road aspect: geom;
			species building aspect: geom;
			species people aspect: circle;
		}

		display population_chart refresh: every(10 #cycles) {
			chart "Covid-19 spreading simulation" type: series {
				data "susceptible" value: nb_people_not_infected color: #green;
				data "infected" value: nb_people_infected color: #red;
				data "vaccinated" value: (nb_people_vaccinated_first_dose + nb_people_vaccinated_second_dose + nb_people_fully_vaccinated) color: #blue;
				data "recovered" value: nb_people_recovered color: #purple;
				data "dead" value: nb_deaths color: #orange;
			}

		}

		display vaccine_chart refresh: every(10 #cycles) {
			chart "Vaccination process" type: series {
				data "vaccinated with the first dose" value: nb_people_vaccinated_first_dose color: #blue;
				data "vaccinated with the second dose" value: nb_people_vaccinated_second_dose color: #orange;
				data "fully vaccinated" value: nb_people_fully_vaccinated color: #green;
				data "deaths of the vaccinated people" value: nb_deaths_vaccinated_people color: #red;
			}

		}

	}

}
