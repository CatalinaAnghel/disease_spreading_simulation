/**
* Name: mers_spreading_model
* Author: Florina-Catalina Anghel
* Based on the Luneray's Flu example
* Tags: disease spreading, MERS, Middle East Respiratory Syndrome, camel meat, camel-human transmission, human-human transmission
*/
model mers_spreading_model

global {
// experiment settings
	int nb_people <- 1000;
	int nb_infected_init <- 50;
	float max_health <- 1.0;
	float step <- 15 #mn;
	int minimum_exposure <- 1;
	int nb_days <- 0;
	float travel_probability <- 0.05;

	// environmental settings:
	file roads_shapefile <- file("../includes/jeddah_roads.shp");
	file buildings_shapefile <- file("../includes/jeddah_buildings.shp");
	geometry shape <- envelope(roads_shapefile);
	//clean or not the data
	bool clean_data <- true;
	//tolerance for reconnecting nodes
	float tolerance <- 3.0;
	//if true, split the lines at their intersection
	bool split_lines <- true;
	//if true, keep only the main connected components of the network
	bool reduce_to_main_connected_components <- true;
	graph road_network;

	// transmission settings:
	float asymptomatic_rate <- 0.153; // 15.3% of the infected people are asymptomatic
	float asymptomatic_transmission_rate <- 0.0001;
	float symptomatic_transmission_rate <- 0.023; //https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6759265/
	float mask_infection_rate <- 0.23; // 23% of the susceptible people that wear masks correctly will be infected
	int nb_minimum_days_carrier <- 2 #day;
	int nb_maximum_days_carrier <- 14 #day;
	float transmission_distance <- 1.5 #m;
	float camel_products_transmission_rate <- 0.386; // https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7692456/
	float unproperly_cooked_food_probability <- 0;
	float reinfection_probability <- 0.1;

	// disease prevention settings:
	bool mandatory_masks <- false;
	bool quarantine <- false;
	float wear_masks_rate <- 0.43;
	int nb_people_with_masks <- int(wear_masks_rate * nb_people);

	// mortality rates (gender, age, comorbidities):
	float male_mortality_rate <- 0.673; // 67.3% from the total deaths are male.
	// age mortality rates:
	float age_20_mortality_rate <- 0;
	float age_40_mortality_rate <- 0.236;
	float age_60_mortality_rate <- 0.291;
	float age_over_61_mortality_rate <- 0.473;
	// comorbidities mortality rates:
	list<float> comorbidities_rates <- [0.20732, 0.31915, 0.4643];
	int nb_people_infected <- nb_infected_init update: people count (each.is_infected);
	int nb_people_not_infected <- nb_people - nb_infected_init update: people count (each.is_susceptible);
	int nb_quarantined_people <- 0 update: people count (each.is_quarantined);
	int nb_people_recovered <- 0 update: people count (each.is_recovered);
	int nb_deaths <- 0;
	int nb_females <- 0 update: people count (each.gender = 1);

	// population:
	int nb_people_under_20 <- 0 update: people count (each.age < 20);
	int nb_people_under_40 <- 0 update: people count (each.age < 40 and each.age >= 20);
	int nb_people_under_60 <- 0 update: people count (each.age < 60 and each.age >= 40);
	int nb_people_over_60 <- 0 update: people count (each.age >= 60);
	int nb_asymptomatic_people <- 0 update: people count (each.is_asymptomatic and each.is_infected);
	float people_under_20_rate <- 0.331;
	float people_under_40_rate <- 0.299;
	float people_under_60_rate <- 0.231;

	// death related data
	int nb_female_deaths <- 0;
	int nb_under_20yo_deaths <- 0;
	int nb_under_40yo_deaths <- 0;
	int nb_under_60yo_deaths <- 0;
	int nb_over_60yo_deaths <- 0;
	int nb_deaths_without_comorbidities <- 0;
	int nb_deaths_one_comorbidity <- 0;
	int nb_deaths_two_comorbidities <- 0;
	float female_max_health_update <- 0.1;
	float male_max_health_update <- 0.12;

	// camel products
	int nb_camel_products_purchases <- 0;
	int nb_camel_products_infections <- 0;

	// rates:
	float infected_rate update: nb_people_infected / nb_people * 100;

	init {
		list<geometry> clean_lines <- clean_data ? clean_network(roads_shapefile.contents, tolerance, split_lines, reduce_to_main_connected_components) : roads_shapefile.contents;
		create road from: clean_lines;
		road_network <- as_edge_graph(road);
		create building from: buildings_shapefile;
		create people number: nb_people {
			location <- any_location_in(one_of(building));
			home_building <- one_of(building);
			home <- any_location_in(home_building);
		}
		// infect some people
		ask nb_infected_init among people {
			is_infected <- true;
		}

		// a group of the agents will wear masks 
		ask (wear_masks_rate * nb_people) among people {
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
		ask int(nb_people * people_under_40_rate) among remaining_people {
			age <- rnd(19) + 20;
		}

		list<people> remaining_people <- people where (each.age = 0);
		ask int(nb_people * people_under_60_rate) among remaining_people {
			age <- rnd(19) + 40;
		}

		list<people> remaining_people <- people where (each.age = 0);
		ask remaining_people {
			age <- rnd(39) + 60;
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
// physical attributes:
	int nb_comorbidities;
	int age;
	float speed;
	float size;
	int gender;
	rgb color;
	float health <- rnd(max_health);

	// disease-related attributes
	bool is_infected <- false;
	bool asympt_handle <- false;
	bool is_asymptomatic <- true;
	bool is_recovered <- false;
	bool is_susceptible <- false;
	int infection_cycle <- 0;
	int recovery_cycle <- 0;
	bool is_quarantined;
	bool quarantined_home;
	float total_mortality_probability <- 0;
	bool will_develop_symptoms <- false;
	building home_building <- nil;
	int current_day_exposure <- 0;
	bool wears_mask <- false;

	// location settings
	point home;
	point target;

	// camel products
	int camel_products_purchase_period;

	init {
		quarantined_home <- false;
		is_quarantined <- false;
		speed <- (2 + rnd(3)) #km / #h;
		gender <- rnd_choice([0::0.5, 1::0.5]);
		nb_comorbidities <- rnd_choice([0::0.45, 1::0.3, 2::0.25]);
		camel_products_purchase_period <- (rnd(6) + 1);
	}

	reflex stay when: target = nil and !is_quarantined {
	// stay or move to one of the buildings
		if flip(travel_probability) {
			target <- any_location_in(one_of(building));
		}

	}

	reflex move when: target != nil and !is_quarantined {
		do goto target: target on: road_network;
		if (location = target) {
			target <- nil;
		}

	}

	reflex stay_at_home when: is_quarantined and !quarantined_home {
	// go home and stay there
		do goto target: home on: road_network;

		if location = home {
			target <- nil;
			quarantined_home <- true;
		}

	}

	reflex get_quarantined when: !is_asymptomatic and is_infected and cycle >= infection_cycle + nb_minimum_days_carrier / step and quarantine {
		is_quarantined <- true;
		list<people> flatmates <- people where (each.home_building = self.home_building);
		ask flatmates {
			if !is_quarantined {
				is_quarantined <- true;
			}

		}

	}

	reflex infect when: is_infected and cycle >= infection_cycle + nb_minimum_days_carrier / step {
		float rate <- is_asymptomatic ? asymptomatic_transmission_rate : symptomatic_transmission_rate;
		if flip(rate) {
			ask people at_distance transmission_distance {
				current_day_exposure <- current_day_exposure + 1;
				if ((!is_infected and !is_recovered and current_day_exposure >= minimum_exposure) or (is_recovered and flip(reinfection_probability))) and ((wears_mask and
				flip(mask_infection_rate)) or !wears_mask) {
					is_infected <- true;
					is_susceptible <- false;
					is_recovered <- false;
					infection_cycle <- cycle;
				}

			}

		}

	}

	reflex die when: health <= 0 {
		nb_people <- nb_people - 1;
		nb_deaths <- nb_deaths + 1;

		// age groups comorbidities
		switch age {
			match_between [0, 20] {
				nb_under_20yo_deaths <- nb_under_20yo_deaths + 1;
			}

			match_between [21, 40] {
				nb_under_40yo_deaths <- nb_under_40yo_deaths + 1;
			}

			match_between [41, 60] {
				nb_under_60yo_deaths <- nb_under_60yo_deaths + 1;
			}

			match_between [61, 100] {
				nb_over_60yo_deaths <- nb_over_60yo_deaths + 1;
			}

		}

		//gender comorbidities
		if (gender = 1) {
			nb_female_deaths <- nb_female_deaths + 1;
		}

		// comorbidities related deaths:
		switch nb_comorbidities {
			match 0 {
				nb_deaths_without_comorbidities <- nb_deaths_without_comorbidities + 1;
			}

			match 1 {
				nb_deaths_one_comorbidity <- nb_deaths_one_comorbidity + 1;
			}

			match 2 {
				nb_deaths_two_comorbidities <- nb_deaths_two_comorbidities + 1;
			}

		}

		do die;
	}

	reflex become_symptomatic when: is_infected and (is_asymptomatic and flip(asymptomatic_rate)) and !asympt_handle {
	// the agent will have symptoms
		will_develop_symptoms <- true;
		asympt_handle <- true;
	}

	reflex update_health when: is_infected and cycle > infection_cycle + rnd(5) #day / step and will_develop_symptoms {
		is_asymptomatic <- false;
		// compute the mortality rate based on age and comorbidities
		float age_probability <- 0.0;
		switch age {
			match_between [0, 20] {
				age_probability <- age_20_mortality_rate;
			}

			match_between [21, 40] {
				age_probability <- age_40_mortality_rate;
			}

			match_between [41, 60] {
				age_probability <- age_60_mortality_rate;
			}

			match_between [61, 100] {
				age_probability <- age_over_61_mortality_rate;
			}

		}

		total_mortality_probability <- age_probability * comorbidities_rates[nb_comorbidities];
		if flip(total_mortality_probability) {
		// the agent will become sicker
			float health_max_update_value <- 0;
			health_max_update_value <- (gender = 1) ? female_max_health_update : male_max_health_update;
			health <- health - rnd(health_max_update_value);
		} else if cycle >= infection_cycle + (rnd(10) + 2) #day / step {
		// the agent will feel better
			health <- health + rnd(0.05);
			if health > 1.0 {
				health <- 1.0;
			}

		}

	}

	reflex get_healthy when: is_infected and cycle = infection_cycle + nb_maximum_days_carrier / step {
	// the agent will recover from the disease
		is_asymptomatic <- true;
		is_recovered <- true;
		recovery_cycle <- cycle;
		nb_people_recovered <- nb_people_recovered + 1;

		// update the agent's health
		health <- health + rnd(1);
		if health > 1.0 {
			health <- 1.0;
		}

		// the agent is not quarantined anymore
		is_quarantined <- false;
		quarantined_home <- false;
		asympt_handle <- false;
		will_develop_symptoms <- false;
		list<people> flatmates <- people where (each.home_building = self.home_building);
		ask flatmates {
			if !is_infected{
				is_quarantined <- false;
			quarantined_home <- false;
			}
			
		}

		is_infected <- false;
	}

	reflex consumes_camel_products when: every(camel_products_purchase_period #day) and !is_infected {
	// simulate the camel-human transmission
		nb_camel_products_purchases <- nb_camel_products_purchases + 1;
		if (flip(camel_products_transmission_rate * unproperly_cooked_food_probability)) {
			is_infected <- true;
			is_susceptible <- false;
			is_recovered <- false;
			infection_cycle <- cycle;
			nb_camel_products_infections <- nb_camel_products_infections + 1;
			write "A person has been infected by consuming unprocessed camel products";
		}

	}

	reflex become_susceptible when: !is_infected and ((is_recovered and cycle > recovery_cycle + 6 #month / step)) {
	// after 6 months, the person is susceptible
		is_susceptible <- true;
		is_recovered <- false;
	}

	reflex reset_exposure when: every(1 #day) {
		current_day_exposure <- 0;
	}

	reflex get_old when: every(1 #year) and cycle >= 1 #year / step {
		age <- age + 1;
	}

	aspect circle {
		draw circle(5) color: is_infected ? #red : #green;
	}

}

// road
species road {

	aspect geom {
		draw shape color: #black;
	}

}

// building
species building {

	aspect geom {
		draw shape color: #gray;
	}

}

experiment mers_spreading_experiment type: gui {
	parameter "Number of people infected at init" var: nb_infected_init min: 1 max: 1000;
	parameter "The masks are mandatory" var: mandatory_masks min: 0 max: 1;
	parameter "The probability to leave the current building" var: travel_probability min: 0 max: 1 category: "Probabilities";
	parameter "The sick people will be quarantined" var: quarantine min: 0 max: 1;
	parameter "The probability that the person will not properly cook the products" var: unproperly_cooked_food_probability min: 0 max: 1 category: "Probabilities";
	parameter "The probability that a recovered person will be reinfected" var: reinfection_probability min: 0 max: 1 category: "Probabilities";
	output {
		monitor "Remaining population" value: nb_people;
		monitor "The number of asymptomatic people:" value: nb_asymptomatic_people;
		monitor "Number of females" value: nb_females;
		monitor "Deaths" value: nb_deaths;
		monitor "Recovered" value: nb_people_recovered;
		monitor "Infected people rate (total)" value: infected_rate;
		monitor "Currently infected people" value: nb_people_infected;
		monitor "Current day of the simulation" value: nb_days;
		monitor "Population under 20 years old" value: nb_people_under_20;
		monitor "Population under 40 years old" value: nb_people_under_40;
		monitor "Population under 60 years old" value: nb_people_under_60;
		monitor "Population over 60 years old" value: nb_people_over_60;
		monitor "Female deaths" value: nb_female_deaths;
		monitor "Deaths (under 20)" value: nb_under_20yo_deaths;
		monitor "Deaths (under 40)" value: nb_under_40yo_deaths;
		monitor "Deaths (under 60)" value: nb_under_60yo_deaths;
		monitor "Deaths (over 60)" value: nb_over_60yo_deaths;
		monitor "Deaths (without comorbidities)" value: nb_deaths_without_comorbidities;
		monitor "Deaths (one comorbidity)" value: nb_deaths_one_comorbidity;
		monitor "Deaths (two comorbidities)" value: nb_deaths_two_comorbidities;
		display map {
			species road aspect: geom;
			species building aspect: geom;
			species people aspect: circle;
		}

		display population_chart_display refresh: every(10 #cycles) {
			chart "Disease spreading" type: series {
				data "susceptible" value: nb_people_not_infected color: #green;
				data "infected" value: nb_people_infected color: #red;
				data "recovered" value: nb_people_recovered color: #purple;
				data "dead" value: nb_deaths color: #orange;
			}

		}

		display camel_products_chart_display refresh: every(10 #cycles) {
			chart "Camel products" type: series {
				data "camel products purchases" value: nb_camel_products_purchases color: #green;
				data "camel products infections" value: nb_camel_products_infections color: #red;
			}

		}

	}

}
